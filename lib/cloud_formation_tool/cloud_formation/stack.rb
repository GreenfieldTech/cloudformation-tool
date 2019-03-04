require 'aws-sdk-cloudformation'
require 'aws-sdk-autoscaling'

module CloudFormationTool
  class CloudFormation
    
    class Stack
      include Enumerable
      include Storable
      include CloudFormationTool
      
      attr_reader :name
      
      def initialize(name)
        @name = name
        @seenev = Set.new
        @watch_timeouts = 0
        @nested_stacks = Hash[]
      end
      
      def delete
        awscf.delete_stack  stack_name: @name
      end
      
      def exist?
        begin
          awscf.describe_stacks stack_name: name
          true
        rescue Aws::CloudFormation::Errors::ValidationError => e
          false
        end
      end
      
      def update(url, filepath, params = {})
        log "Updating existing stack '#{name}' from '#{filepath}' params #{params.inspect}"
        valid_check do
          resp = awscf.update_stack({
            stack_name: @name,
            template_url: url,
            capabilities: %w(CAPABILITY_IAM CAPABILITY_NAMED_IAM),
            parameters: params.collect do |k,v|
              {
                parameter_key: k.to_s,
                parameter_value: v.to_s,
                use_previous_value: false,
              }
            end
          })
          resp.stack_id
        end
      end
      
      def create(template, params = {})
        @template = CloudFormation.parse(template).to_yaml(params)
        url = upload(make_filename('yaml'), @template, gzip: false)
        return update(url, template, params) if exist?
        log "Creating stack '#{name}' from '#{template}' params #{params.inspect}"
        valid_check do
          resp = awscf.create_stack({
            stack_name: @name,
            template_url: url,
            capabilities: %w(CAPABILITY_IAM CAPABILITY_NAMED_IAM),
            on_failure: "DO_NOTHING", ##"ROLLBACK",
            parameters: params.collect do |k,v|
              {
                parameter_key: k.to_s,
                parameter_value: v.to_s,
                use_previous_value: false,
              }
            end
          })
          @stack_id = resp.stack_id
        end
      end
      
      def stack_id
        @stack_id ||= awscf.describe_stacks(stack_name: @name).stacks.first.stack_id
      end
      
      def output
        begin
          key_width = 0
          resp = awscf.list_exports
          resp.exports.select do |exp|
            exp.exporting_stack_id == stack_id
          end.each do |exp|
            key_width = [ key_width, exp.name.length ].max
          end.collect do |exp|
            "%-#{key_width}s: %s" % [ exp.name, exp.value ]
          end
        rescue Aws::CloudFormation::Errors::ValidationError => e
          raise CloudFormationTool::Errors::AppError, "Failed to get resources: #{e.message}"
        end
      end
      
      def resources
        begin
          awscf.list_stack_resources(stack_name: @name).each do |resp|
            resp.stack_resource_summaries.each do |res|
              yield res
              if res.resource_type == 'AWS::CloudFormation::Stack'
                Stack.new(res.physical_resource_id).resources do |nested_res|
                  yield nested_res
                end
              end
            end
          end
        rescue Aws::CloudFormation::Errors::ValidationError => e
          raise CloudFormationTool::Errors::AppError, "Failed to get resources: #{e.message}"
        end
      end
      
      def asgroups
        output = []
        resources do |res|
          output << res if res.resource_type == 'AWS::AutoScaling::AutoScalingGroup'
        end
        output.collect do |res|
          res.extend(CloudFormationTool)
          res.instance_eval do
            def group
              Aws::AutoScaling::AutoScalingGroup.new(self.physical_resource_id, client: awsas).reload
            end
          end
          res
        end
      end
      
      def cdns
        output = []
        resources do |res|
          output << res if res.resource_type == 'AWS::CloudFront::Distribution'
        end
        output.collect do |res|
          res.extend(CloudFrontDistribution)
        end
      end
      
      def see_events
        each { |e| @seenev << e.event_id }
      end
      
      def monitor(start_time = nil)
        @nested_stacks = Hash[]
        done = false
        begin
          until done
            reverse_each do |ev|
              next if @seenev.add?(ev.event_id).nil?
              text = "#{ev.timestamp.strftime "%Y-%m-%d %H:%M:%S"}| " + %w(
                resource_type:40
                logical_resource_id:42
                resource_status
              ).collect { |field|
                (name,size) = field.split(":")
                size ||= 1
                (if name == 'logical_resource_id' and ev.stack_name != self.name
                  logical_nested_stack_name(ev.stack_name) + "|"
                else
                  ''
                end + ev.send(name.to_sym)).ljust(size.to_i, ' ')
              }.join("  ")
              text += " " + ev.resource_status_reason if ev.resource_status =~ /_FAILED/
              if start_time.nil? or start_time < ev.timestamp
                puts text
              end
              check_nested_stack(ev)
              done = is_final_event(ev)
            end
            sleep 1
          end
        rescue CloudFormationTool::Errors::StackDoesNotExistError => e
          puts "Stack #{name} does not exist"
        end
      end
      
      def logical_nested_stack_name(phys_name)
        @nested_stacks[phys_name] || 'unknown'
      end
      
      def nested_stack_name(ev)
        ev.physical_resource_id.split('/')[1]
      end
      
      def check_nested_stack(ev)
        return unless ev.resource_type == "AWS::CloudFormation::Stack" and
          ev.logical_resource_id != self.name # not nested stack
        return if @nested_stacks.has_key? ev.logical_resource_id # seeing the first or last nested stack event - ignoring
        @nested_stacks[nested_stack_name(ev)] = ev.logical_resource_id
      end
      
      def is_final_event(ev)
        ev.resource_type == "AWS::CloudFormation::Stack" and
        ev.resource_status =~ /(_COMPLETE|_FAILED)$/ and
        ev.logical_resource_id == self.name
      end
      
      def tracked_stacks
        [ self.name ] + @nested_stacks.keys.compact
      end
      
      def each
        tracked_stacks.each do |name|
          events_for(name) do |ev|
            yield ev
          end
        end
      end
      
      def events_for(stack_name)
        token = nil
        sleep(if @_last_poll_time.nil?
          0
          else
            diff = Time.now - @_last_poll_time
            if diff < 1
              diff
            else
              0
            end
          end)
        begin
          resp = awscf.describe_stack_events stack_name: stack_name, next_token: token
          @watch_timeouts = 0
          resp.stack_events.each do |ev|
            yield ev
          end
        rescue Aws::CloudFormation::Errors::Throttling => e
          sleep 1
          retry
        rescue Seahorse::Client::NetworkingError => e # we get this when there's a timeout
          if (@watch_timeouts += 1) > 5
            raise CloudFormationTool::Errors::AppError, "Too many timeouts!"
          else
            retry
          end
        rescue Aws::CloudFormation::Errors::ValidationError => e
          if e.message =~ /does not exist/
            if stack_name == self.name
              raise CloudFormationTool::Errors::StackDoesNotExistError, "Stack does not exist"
            end
            # ignore "does not exist" errors on nested stacks - we may try to poll them before
            # they actually exist. We'll just try later
          else
            raise e
          end
        end
      end
      
      private
      
      def valid_check
        begin
          yield
        rescue Aws::CloudFormation::Errors::ValidationError => e
          raise CloudFormationTool::Errors::ValidationError, "Stack validation error: #{e.message}"
        end  
      end
    end

  end
end
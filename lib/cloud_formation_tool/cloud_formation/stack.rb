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
      
      def create(template, params = {})
        tmpl = CloudFormation.parse(template).to_yaml(params)
        url = upload(make_filename('yaml'), tmpl, false)
        return update(url, template, params) if exist?
        log "Creating stack '#{name}' from '#{template}' params #{params.inspect}"
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
        resp.stack_id
      end
      
      def resources
        begin
          resp = awscf.describe_stack_resources  stack_name: @name
          resp.stack_resources
        rescue Aws::CloudFormation::Errors::ValidationError => e
          raise CloudFormationTool::Errors::AppError, "Failed to get resources: #{e.message}"
        end
      end
      
      def asgroups
        resources.select do |res|
          res.resource_type == 'AWS::AutoScaling::AutoScalingGroup'
        end
      end
      
      def see_events
        each { |e| @seenev << e.event_id }
      end
      
      def monitor(start_time = nil)
        done = false
        begin
          until done
            reverse_each do |ev|
              next if @seenev.add?(ev.event_id).nil?
              text = "#{ev.timestamp.strftime "%Y-%m-%d %H:%M:%S"}| " + %w(
                resource_type:40
                logical_resource_id:38
                resource_status
              ).collect { |field|
                (name,size) = field.split(":")
                size ||= 1
                ev.send(name.to_sym).ljust(size.to_i, ' ')
              }.join("  ")
              text += " " + ev.resource_status_reason if ev.resource_status =~ /_FAILED/
              if start_time.nil? or start_time < ev.timestamp
                puts text
              end
              done = (ev.resource_type == "AWS::CloudFormation::Stack" and ev.resource_status =~ /(_COMPLETE|_FAILED)$/)
            end
          end
        rescue CloudFormationTool::Errors::StackDoesNotExistError => e
          puts "Stack #{name} does not exist"
        end
      end
      
      def each
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
          resp = awscf.describe_stack_events stack_name: name, next_token: token
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
            raise CloudFormationTool::Errors::StackDoesNotExistError, "Stack does not exist"
          else
            raise e
          end
        end
      end
    end

  end
end
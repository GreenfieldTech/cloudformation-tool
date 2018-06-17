module CloudFormationTool
  module CLI
    
    class Scale < Clamp::Command
      include CloudFormationTool
      
      parameter "STACK_NAME", "Name of the stack to recycle servers in"
      parameter "ASG_NAME", "Name of the auto scaling group in which to recycle all servers"
      parameter "SCALE", "Number of servers desired"
      
      def grpstate(grp)
        grp.instances.collect { |i| i.lifecycle_state }.reduce({}) { |m,s| m[s] = (m[s] || 0) + 1; m }
      end
      
      def grpstatedesc(grp)
        grpstate(grp).collect{|s,c|"#{c} #{s}"}.join(", ")
      end
      
      def stable_scale(grp, scale)
        state = grpstate(grp)
        state["InService"].eql? scale.to_i and state.delete_if{|k|k.eql? "InService"}.empty?
      end
      
      def execute
        debug "Starting scale operations"
        st = CloudFormation::Stack.new(stack_name)
        st.asgroups.select do |res|
          debug "Checking group #{res.logical_resource_id}"
          asg_name.nil? or (res.logical_resource_id == asg_name)
        end.collect do |res|
          debug "Scaling #{res.logical_resource_id}"
          Thread.new do
            grp = res.group
            debug "Current capacity: #{grp.desired_capacity}, setting to #{scale}"
            grp.set_desired_capacity(desired_capacity: scale)
            last_state = nil
            until stable_scale(grp, scale)
              log "Current scaling status: #{last_state = grpstatedesc(grp)}" unless last_state.eql? grpstatedesc(grp)
              sleep 3
              grp.reload
            end
            log "Done updating - current scale: #{grpstatedesc(grp)}"
          end
        end.each(&:join)
      end
    end
  end
end

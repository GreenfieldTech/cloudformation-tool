module CloudFormationTool
  module CLI
    
    class Groups < Clamp::Command
      include CloudFormationTool
      
      parameter "STACK_NAME", "Name of the stack to list Autoscaling groups from"
      
      def execute
        st = CloudFormation::Stack.new(stack_name)
        output = st.asgroups.collect do |res|
          {
            name: res.logical_resource_id,
            res: res.physical_resource_id,
            len: res.logical_resource_id.length
          }
        end
        width = output.collect { |g| g[:name].length }.max
        output.collect do |grp|
          puts grp[:name].ljust(width, ' ') + "\t => " + grp[:res]
        end
      end
    end
  end
end

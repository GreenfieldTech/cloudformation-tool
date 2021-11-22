module CloudFormationTool
  module CLI
    
    class Services < Clamp::Command
      include CloudFormationTool
      
      parameter "STACK_NAME", "Name of the stack to list Fargate services from"
      
      def execute
        st = CloudFormation::Stack.new(stack_name)
        output = st.fargate_services.collect do |res|
          {
            name: res.logical_resource_id,
            res: res.physical_resource_id,
            len: res.logical_resource_id.length
          }
        end
        width = output.collect { |g| g[:name].length }.max
        output.collect do |svc|
          puts svc[:name].ljust(width, ' ') + "\t => " + svc[:res]
        end
      end
    end
  end
end

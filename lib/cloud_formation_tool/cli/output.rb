require 'uri'
require 'net/http'

module CloudFormationTool
  module CLI
    class Output < Clamp::Command
      
      parameter 'STACK_NAME', 'Name of the stack to create. Defaults to directory name'
      
      def execute
        st = CloudFormation::Stack.new(stack_name)
        puts st.output
      end
      
    end
  end
end
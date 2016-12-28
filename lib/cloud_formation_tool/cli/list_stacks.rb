module CloudFormationTool
  module CLI
    
    class ListStacks < Clamp::Command
      include CloudFormationTool
      
      def execute
        awscf.describe_stacks.stacks.each do |stack|
          puts stack.stack_name.ljust(30,' ') + stack.stack_status
        end
      end
      
    end
  end
end
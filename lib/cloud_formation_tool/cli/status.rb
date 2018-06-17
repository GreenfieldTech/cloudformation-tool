module CloudFormationTool
  module CLI
    
    class Status < Clamp::Command
      
      parameter "STACK_NAME", "Name of the stack to delete"
        
      def execute
        if CloudFormation::Stack.new(stack_name).exist?
          log "OK"
        else
          error "Stack #{stack_name} does not exist"
        end
      end

    end
  end
end
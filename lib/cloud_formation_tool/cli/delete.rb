module CloudFormationTool
  module CLI
    
    class Delete < Clamp::Command
      
      parameter "STACK_NAME", "Name of the stack to delete"
      
      def execute
        st = CloudFormation::Stack.new(stack_name)
        start = Time.now
        st.delete
        log "Deleted stack #{stack_name}"
        st.monitor(start)
      end
      
    end
  end
end
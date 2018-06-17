module CloudFormationTool
  module CLI
    
    class Monitor < Clamp::Command
      
      parameter 'STACK_NAME', "Name of the stack to monitor"
      
      option [ "-a", "--all" ], :flag, "Don't skip old events"
      
      def execute
        begin
          st = CloudFormation::Stack.new(stack_name)
          st.see_events unless all?
          while true
            st.monitor
            sleep 1
          end
        rescue CloudFormationTool::Errors::StackDoesNotExistError => e
          error "Stack #{stack_name} does not exist"
        rescue SystemExit, Interrupt => e
          # CTRL-C out of the loop
          puts "\n"
        end
      end
      
    end
  end
end
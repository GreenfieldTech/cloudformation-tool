module CloudFormationTool
  module CLI
    
    class Invalidate < Clamp::Command
      include CloudFormationTool
      
      parameter "STACK_NAME", "Name of the stack to invalidate CloudFront caches in"
      
      def execute
        st = CloudFormation::Stack.new(stack_name)
        st.cdns.collect do |res|
          Thread.new do
            log "Creating cache invalidation for #{res.distribution.id} #{res.domain_names} /*"
            inv = res.invalidate("/*")
            log "Invalidation #{inv.id}: #{inv.status}"
            inv.wait
            log "Invalidation #{inv.id}: #{inv.status}"
          end
        end.each(&:join).length > 0 or error "No valid CloudFront distributions found"
      end
    end
  end
end
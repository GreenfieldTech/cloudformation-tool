module CloudFormationTool
  class CloudFormation
    
    module CloudFrontDistribution
      include CloudFormationTool
      
      def distribution
        @__dist ||= awscdn.get_distribution(id: self.physical_resource_id).distribution
      end
      
      def domain_names
        distribution.distribution_config.aliases.items.join(",")
      end
        
      def invalidate(path_expression)
        callerref = Time.now.strftime("%Y%m%d%H%M%S")
        awscdn.create_invalidation(
          distribution_id: self.physical_resource_id,
          invalidation_batch: {
            paths: { quantity: 1, items: [ path_expression ] },
            caller_reference: callerref
          }
        ).invalidation.tap do |i|
          i.extend(CloudFrontInvalidation)
          i.distribution_id = self.physical_resource_id
        end
      end

    end
    
    module CloudFrontInvalidation
      include CloudFormationTool
      
      def distribution_id= distid
        @distid = distid
      end
      
      def status
        awscdn.get_invalidation(distribution_id: @distid, id: self.id).invalidation.status
      end
      
      def wait
        while self.status == "InProgress"
          sleep 5
        end
      end

    end
  end
end
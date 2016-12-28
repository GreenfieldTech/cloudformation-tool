require 'net/http'

module CloudFormationTool
  class CloudFormation
    
    class LambdaCode
      include Storable
      
      def initialize(url)
        log "Downloading Lambda code from #{url}"
        res = fetch(url)
        
        @s3_url = URI(upload(make_filename(url.split('.').last), res.body, res['content-type']))
        log "uploaded Lambda function to #{@s3_url}"
      end
      
      def fetch(uri_str, limit = 10)
        raise ArgumentError, 'too many HTTP redirects' if limit == 0
        response = Net::HTTP.get_response(URI(uri_str))
        case response
        when Net::HTTPSuccess then
          response
        when Net::HTTPRedirection then
          location = response['location']
          log "redirected to #{location}"
          fetch(location, limit - 1)
        else
          raise AppError, "Error downloading #{url}: #{response.value}"
        end
      end
      
      def to_cloudformation
        {
          'S3Bucket' => @s3_url.hostname.split('.').first,
          'S3Key' => @s3_url.path[1..-1]
        }
      end
    end

  end
end
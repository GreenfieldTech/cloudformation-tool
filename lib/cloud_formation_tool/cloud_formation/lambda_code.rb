require 'net/http'
require 'zip'

module CloudFormationTool
  class CloudFormation
    
    class LambdaCode
      include Storable
      
#      def initialize(url)
#        log "Downloading Lambda code from #{url}"
#        res = fetch(url)
#        
#        @s3_url = URI(upload(make_filename(url.split('.').last), res.body, mime_type: res['content-type'], gzip: false))
#        log "uploaded Lambda function to #{@s3_url}"
#      end
      
      def initialize(url: nil, path: nil)
        log "Downloading Lambda code from #{url}"
        case url
          when nil
            @s3_url = URI(upload(make_filename(path.split('/').last), fetch_path(path).read, gzip: false))
          else
            res = fetch_url(url)
            @s3_url = URI(upload(make_filename(url.split('.').last), res.body, mime_type: res['content-type'], gzip: false))
          end
        log "uploaded Lambda function to #{@s3_url}"
      end
      
      def fetch_path(path_str)
        if File.directory?(path_str)
          Zip::ZipFile.open(path_str.split('/').last, Zip::ZipFile::CREATE) do |zipfile|
              Dir[File.join(path_str, '*')].each do |file|
                zipfile.add(file.sub(path_str, ''), file)
              end
          end
        end
        File.open(path_str, "rb") #if its a zip - will it open the zip or the folder (by the same name)?
      end
      
      def fetch_url(uri_str, limit = 10)
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
          raise CloudFormationTool::Errors::AppError, "Error downloading #{url}: #{response.value}"
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
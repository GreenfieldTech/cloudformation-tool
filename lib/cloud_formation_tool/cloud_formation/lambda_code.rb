require 'net/http'
require 'zip'

module CloudFormationTool
  class CloudFormation
    
    class LambdaCode
      include Storable
      
      def initialize(url: nil, path: nil)
        log "Downloading Lambda code from #{url}#{path}"
        case url
          when nil
            @s3_url = if File.directory?(path)
                        URI(upload(make_filename(path.split('/').last), fetch_from_folder(path), mime_type: 'application/zip',  gzip: false))
                      else
                        URI(upload(make_filename(path.split('/').last), File.open(path, "rb").read, gzip: false))
                      end
          else
            res = fetch_from_url(url)
            @s3_url = URI(upload(make_filename(url.split('.').last), res.body, mime_type: res['content-type'], gzip: false))
          end
        log "uploaded Lambda function to #{@s3_url}"
      end
      
      def fetch_from_folder(path_str)
        begin
          temp_file = Tempfile.new("#{path_str.split('/').last}.zip")
          Zip::ZipOutputStream.open(temp_file) { |zos| }
          Zip::ZipFile.open(temp_file.path, Zip::ZipFile::CREATE) do |zipfile|
            Dir[File.join(path_str, '*')].each do |file|
              zipfile.add(file.sub("#{path_str}/", ''), file)
            end
          end
          zip_data = File.read(temp_file.path)
        ensure
          temp_file.close
          temp_file.unlink
        end
        zip_data
      end
      
    def fetch_from_url(uri_str)
      $__fetch_cache ||= Hash.new do |h, url|
        h[url] = fetch_from_url_real(url)
      end
      $__fetch_cache[uri_str]
    end
    
    def fetch_from_url_real(uri_str, limit = 10)
        raise ArgumentError, 'too many HTTP redirects' if limit == 0
        response = Net::HTTP.get_response(URI(uri_str))
        case response
        when Net::HTTPSuccess then
          response
        when Net::HTTPRedirection then
          location = response['location']
          log "redirected to #{location}"
          fetch_from_url_real(location, limit - 1)
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
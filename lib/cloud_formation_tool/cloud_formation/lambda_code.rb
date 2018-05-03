require 'net/http'
require 'zip'

module CloudFormationTool
  class CloudFormation
    
    class LambdaCode
      include Storable
      
      def initialize(code, tpl)
        @data = code
        @data['Url'] = @data.delete 'URL' if @data.key? 'URL' # normalize to CF convention if seeing old key
        if @data.key? 'Url'
          log "Trying Lambda code from #{@data['Url']}"
          @data['Url'] = url = tpl.resolveVal(@data['Url'])
          return unless url.is_a? String
          log "Downloading Lambda code from #{url}"
          unless already_in_cache(url)
            res = fetch_from_url(url)
            @s3_url = URI(upload(make_filename(url.split('.').last), res.body, mime_type: res['content-type'], gzip: false))
            log "uploaded Lambda function to #{@s3_url}"
          end
        elsif @data.key? 'Path'
          @data['Path'] = path = tpl.resolveVal(@data['Path'])
          return unless path.is_a? String
          log "Reading Lambda code from #{path}"
          path = if path.start_with? "/" then path else "#{tpl.basedir}/#{path}" end
          if File.directory?(path)
            @s3_url = URI(upload(make_filename('zip'), zip_path(path), mime_type: 'application/zip', gzip: false))
            log "uploaded Lambda function to #{@s3_url}"
          else # Convert files to ZipFile
            @data.delete 'Path'
            @data['ZipFile'] = File.read(path)
          end
        end
      end
      
      def zip_path(path)
        temp_file = Tempfile.new
        temp_path = temp_file.path + '.zip'
        begin
          Zip::ZipFile.open(temp_path, true) do |zipfile|
            Dir[File.join(path, '**','*')].each do |file|
              zipfile.add(file.sub("#{path}/", ''), file)
            end
          end
          File.read(temp_path)
        ensure
          temp_file.close!
          File.unlink temp_path
        end
      end
      
      def already_in_cache(uri_str, limit = 10)
        raise ArgumentError, 'too many HTTP redirects' if limit == 0
        url = URI(uri_str)
        begin
          Net::HTTP.start(url.host, url.port) do |http|
            request = Net::HTTP::Get.new(url)
            http.request(request) do |response|
              # handle redirects like Github likes to do
              case response
                when Net::HTTPSuccess then
                  check_cached(response['ETag'])
                when Net::HTTPRedirection then
                  location = response['location']
                  log "redirected to #{location}"
                  already_in_cache(location, limit - 1)
                else
                  raise ArgumentError, "Error getting response: #{response}"
              end
            end
          end
        rescue EOFError
        end
        !@s3_url.nil?
      end
      
      def check_cached(etag)
        etag.gsub!(/"/,'') unless etag.nil?
        o = cached_object(etag)
        unless o.nil?
          log 'reusing cached object'
          @s3_url = o.public_url
        end
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
        if @s3_url.nil?
          @data
        else
          {
            'S3Bucket' => @s3_url.hostname.split('.').first,
            'S3Key' => @s3_url.path[1..-1]
          }
        end
      end
    end

  end
end
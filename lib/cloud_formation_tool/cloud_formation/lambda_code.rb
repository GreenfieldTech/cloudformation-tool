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
          debug "Trying Lambda code from #{@data['Url']}"
          @data['Url'] = url = tpl.resolveVal(@data['Url'])
          return unless url.is_a? String
          log "Downloading Lambda code from #{url}"
          if already_in_cache(url)
            debug "Reusing remote cached object instead of downloading"
          else
            res = fetch_from_url(url)
            @s3_url = URI(upload(make_filename(url.split('.').last), res.body, mime_type: res['content-type'], gzip: false))
            log "uploaded Lambda function to #{@s3_url}"
          end
        elsif @data.key? 'Path'
          @data['Path'] = path = tpl.resolveVal(@data['Path'])
          return unless path.is_a? String
          debug "Reading Lambda code from #{path}"
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
        Zip::OutputStream.write_buffer do |zf|
          rdir path do |ent|
            debug "Deflating #{ent}"
            filepath = File.join(path,ent)
            zf.put_next_entry ::Zip::Entry.new(nil, ent, nil, nil, nil, nil, nil, nil, ::Zip::DOSTime.at(File.mtime(filepath).to_i))
            zf.write File.read(filepath) 
          end
        end.string
      end
      
      def already_in_cache(uri_str)
        limit = 10
        url = URI(uri_str)
        until url.nil?
          begin
            raise ArgumentError, 'too many HTTP redirects' if limit == 0
            Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
              request = Net::HTTP::Get.new(url)
              http.request(request) do |response|
                # handle redirects like Github likes to do
                case response
                  when Net::HTTPSuccess then
                    url = nil
                    break if check_cached(response['ETag']) # dont read the body if its already cached
                  when Net::HTTPRedirection then
                    location = response['location']
                    debug "Cache check redirected to #{location}"
                    limit = limit - 1
                    response.body
                    url = URI(location)
                  else
                    raise ArgumentError, "Error getting response: #{response}"
                end
              end
            end
          rescue IOError => e
            retry unless url.nil?
          end
        end
        !@s3_url.nil?
      end
      
      def check_cached(etag)
        unless etag.nil?
          etag.gsub!(/"/,'')
          o = cached_object(etag)
        end
        if o.nil?
          false
        else
          @s3_url = URI(o.public_url)
          true
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
          debug "redirected to #{location}"
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
      
      def rdir path, prefix = '', &block
        ents = []
        (Dir.entries(path) - %w(. ..)).collect do |ent|
          diskpath = File.join(path,ent)
          localpath = prefix.length>0 ? File.join(prefix,ent) : ent
          if block_given?
            if File.directory? diskpath
              rdir diskpath, localpath, &block
            else
              yield localpath
            end
          end
          if File.directory? diskpath
            rdir diskpath, localpath
          else
            ent
          end
        end.flatten
      end
      
    end

  end
end
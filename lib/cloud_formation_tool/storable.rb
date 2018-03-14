require 'digest'
require 'aws-sdk-s3'

module CloudFormationTool
  module Storable
    include CloudFormationTool
    
    def make_filename(ext = '')
      base = "#{File.basename(Dir.pwd)}-#{Time.now.strftime("%Y%m%d%H%M%S")}"
      if ext.empty?
        base
      else
        "#{base}.#{ext}"
      end
    end
    
    def upload(path, content, mime_type: 'text/yaml', gzip: true)
      md5 = Digest::MD5.hexdigest content
      prefix = "#{md5[0]}/#{md5[1..2]}/#{md5}"
      b = Aws::S3::Bucket.new(s3_bucket_name(region), client: awss3(region))
      # return early if we already have a copy of this object stored.
      # if this object was previously uploaded, we use its URLs (and not, for example,
      # do a local copy to the requested path) because this way cloudformation can see
      # that the updated template is exactly the same as the old one and will not force
      # an unneeded update.
      o = b.objects(prefix: "cf-compiled/#{prefix}/").first
      if o.nil?
        # no such luck, we need to actually upload the file
        o = b.object("cf-compiled/#{prefix}/#{path}")
        file_opts = {
          acl: 'public-read',
          body: content,
          content_disposition: 'attachment',
          content_type: mime_type,
          storage_class: 'REDUCED_REDUNDANCY'
        }
        file_opts.merge!({content_encoding: 'gzip'}) if gzip
        o.put(file_opts)
      else
        log "re-using cached object"
      end
      o.public_url
    end
  end
end

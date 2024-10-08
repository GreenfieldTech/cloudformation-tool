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
    
    def cached_object(md5)
      Aws::S3::Bucket.new(s3_bucket_name(region), client: awss3(region)).objects(prefix: prefix(md5)).first
    end
    
    def prefix(md5)
      "cf-compiled/#{md5[0]}/#{md5[1..2]}/#{md5}/"
    end
    
    def upload(path, content, mime_type: 'text/yaml', gzip: true)
      md5 = Digest::MD5.hexdigest content
      b = Aws::S3::Bucket.new(s3_bucket_name(region), client: awss3(region))
      # return early if we already have a copy of this object stored.
      # if this object was previously uploaded, we use its URLs (and not, for example,
      # do a local copy to the requested path) because this way cloudformation can see
      # that the updated template is exactly the same as the old one and will not force
      # an unneeded update.
      o = cached_object(md5)
      if o.nil?
        # no such luck, we need to actually upload the file
        o = b.object(prefix(md5) + path)
        file_opts = {
          acl: 'public-read',
          body: content,
          content_disposition: 'attachment',
          content_type: mime_type,
          storage_class: 'REDUCED_REDUNDANCY'
        }
        ownctl = b.client.get_bucket_ownership_controls(bucket: b.name).ownership_controls
        if ownctl.rules.first.object_ownership == 'BucketOwnerEnforced' then
          # no point in setting ACL
          file_opts.delete :acl
        end
        file_opts.merge!({content_encoding: 'gzip'}) if gzip
        _debug "Uploading S3 object s3://#{b.name}/#{o.key}"
        o.put(file_opts)
      else
        _debug "re-using cached object"
      end
      o.public_url
    end
  end
end

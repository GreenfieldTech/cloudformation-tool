require 'logger'
require 'autoloaded'
require 'socket'
require 'aws-sdk-core'

def logger
  ($__logger ||= Logger.new(STDERR))
end

def log(message = nil, &block)
  logger.info(if message.nil?
    yield
  else
    message
  end)
end

def debug(message = nul, &block)
  logger.debug(if message.nil?
    yield
  else
    message
  end)
end

def warn(message = nul, &block)
  logger.warn(if message.nil?
    yield
  else
    message
  end)
end

def error(message = nul, &block)
  logger.error(if message.nil?
    yield
  else
    message
  end)
end

# Hack AWS SDK to let us find out the Profile's region that it resolved
module Aws
  class SharedConfig
    def profile_region
      c = (if @parsed_credentials and @parsed_credentials[@profile_name] then
        @parsed_credentials[@profile_name]
      elsif @parsed_config and @parsed_config[@profile_name] then
        @parsed_config[@profile_name]
      else
        {}
      end)
      c['region'] || c['aws_region'] || c['sso_region'] || nil
    end
  end
end

module CloudFormationTool
  
  Autoloaded.module do |autoloaded|
    autoloaded.with :CLI 
  end
  
  def find_profile(dir = nil, default = nil)
    dir ||= Dir.pwd
    return default if (dir == "/")
    begin
      return File.read("#{dir}/.awsprofile").chomp
    rescue Errno::ENOENT
      return find_profile(File.dirname(dir))
    end
  end
  
  def region
    $__region ||= ENV['AWS_REGION'] ||
        Aws::SharedConfig.new(profile_name: profile, config_enabled: true).profile_region ||
        ENV['AWS_DEFAULT_REGION'] ||
        'us-east-1'
  end
  
  def profile name = nil
    $__profile ||= name || find_profile(nil, ENV['AWS_PROFILE'] || ENV['AWS_DEFAULT_PROFILE'] || 'default')
  end
  
  def awscreds
    #$__aws_creds ||= Aws::SharedCredentials.new(profile_name: profile)
    config = Aws::SharedConfig.new(profile_name: profile, config_enabled: true)
    $__aws_creds ||= config.credentials
  end
  
  def aws_config
    {
#      credentials: awscreds,
      profile: profile,
      region: region,
      http_read_timeout: 5
    }
  end
  
  def awsec2
    require 'aws-sdk-ec2'
    $__aws_ec2 ||= Aws::EC2::Client.new aws_config
  end
  
  def awss3(s3reg = nil)
    require 'aws-sdk-s3'
    s3reg ||= region
    begin
      ($__aws_s3 ||= {})[region] ||= Aws::S3::Client.new aws_config.merge(region: s3reg)
    rescue Aws::Errors::InvalidSSOToken => e
      raise CloudFormationTool::Errors::AuthError, "SSO login failed: #{e.message}"
    end
  end
  
  def awscf
    require 'aws-sdk-cloudformation'
    $__aws_cf ||= Aws::CloudFormation::Client.new aws_config
  end
  
  def awsas
    require 'aws-sdk-autoscaling'
    $__aws_as ||= Aws::AutoScaling::Client.new aws_config
  end
  
  def awsecs
    require 'aws-sdk-ecs'
    $__aws_ecs ||= Aws::ECS::Client.new aws_config
  end
  
  def awscdn
    require 'aws-sdk-cloudfront'
    $__aws_cdn ||= Aws::CloudFront::Client.new aws_config
  end
  
  def s3_bucket_name(region)
    name = nil
    # see if we already have a cf-templates bucket for this region
    bucket = awss3.list_buckets.buckets.select do |b|
        b.name =~ /cf-templates-(\w+)-#{region}/
    end.first
    
    # otherwise try to create one
    if bucket.nil?
      name = cf_bucket_name(region)
      log "Creating CF template bucket #{name}"
      awss3(region).create_bucket({
        acl: "private",
        bucket: name,
        object_ownership: 'BucketOwnerPreferred'
      }.merge(if region == 'us-east-1' then {} else { create_bucket_configuration: { location_constraint: region } } end))
      awss3(region).delete_public_access_block({bucket: name})
      name
    else
      bucket[:name]
    end
  end
  
  def cf_bucket_name(region, key = nil)
    # generate random key if one wasn't given
    key ||= ((0...12).map { [*'a'..'z',*'0'..'9'][rand(36)] }.join)
    "cf-templates-#{key}-#{region}"
  end

end

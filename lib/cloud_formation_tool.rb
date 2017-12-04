require 'logger'
require 'autoloaded'


def log(message = nil, &block)
  ($__logger ||= Logger.new(STDERR)).info(if message.nil?
    yield
  else
    message
  end)
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
    $__region ||= (ENV['AWS_DEFAULT_REGION'] || 'us-west-1')
  end
  
  def profile
    $__profile ||= find_profile(nil, ENV['AWS_PROFILE'] || ENV['AWS_DEFAULT_PROFILE'] || 'default')
  end
  
  def awscreds
    require 'aws-sdk-core'
    $__aws_creds ||= Aws::SharedCredentials.new(profile_name: profile)
  end
  
  def aws_config
    {
      credentials: awscreds,
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
    ($__aws_s3 ||= {})[region] ||= Aws::S3::Client.new aws_config.merge(region: s3reg)
  end
  
  def awscf
    require 'aws-sdk-cloudformation'
    $__aws_cf ||= Aws::CloudFormation::Client.new aws_config
  end
  
  def awsas
    require 'aws-sdk-autoscaling'
    $__aws_as ||= Aws::AutoScaling::Client.new aws_config
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
      log("Creating CF template bucket #{name}")
      awss3.create_bucket({
        acl: "private",
        bucket: name,
        create_bucket_configuration: { location_constraint: region }
      })
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
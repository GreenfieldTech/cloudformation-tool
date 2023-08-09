require_relative './lib/cloud_formation_tool/version'

Gem::Specification.new do |s|
  s.name = %q{cloudformation-tool}
  s.version = CloudFormationTool::VERSION

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Oded Arbel"]
  s.email = %q{oded.arbel@greenfieldtech.net}
  s.summary = %q{A pre-compiler tool for CloudFormation YAML templates}
  
  s.executables = %w( cftool )
  s.extra_rdoc_files = %w( LICENSE README.md )
  s.files = `find bin lib`.split("\n")
  s.homepage = %q{http://github.com/GreenfieldTech/cloudformation-tool}
  s.licenses = %q{GPL-2.0}
  s.require_paths = %w( lib )

  s.add_dependency 'rake', '>= 12.3.3'
  s.add_dependency 'psych', '>= 4.0'
  s.add_dependency 'clamp', '~> 1'
  s.add_dependency 'aws-sdk-cloudformation', '>= 1'
  s.add_dependency 'aws-sdk-s3', '>= 1'
  s.add_dependency 'aws-sdk-ec2', '>= 1'
  s.add_dependency 'aws-sdk-ecs', '>= 1'
  s.add_dependency 'aws-sdk-autoscaling', '>=1'
  s.add_dependency 'aws-sdk-cloudfront', '>=1'
  s.add_dependency 'autoloaded', '~> 2'
  s.add_dependency 'rubyzip'
end

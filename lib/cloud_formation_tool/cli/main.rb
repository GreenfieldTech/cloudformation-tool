require 'clamp'
require 'io/console'


module CloudFormationTool
  module CLI
    class Main < Clamp::Command
      
      class CFToolHelper
        include CloudFormationTool
      end
      cftool = CFToolHelper.new
      
      banner "Compile and deploy CloudFormation templates"
      
      option [ "-r", "--region" ], "REGION", "AWS Region to use", default: cftool.region do |s|
        $__region = s
      end
      
      option [ "-p", "--profile" ], "PROFILE", "AWS credentials profile to use", default: cftool.profile do |s|
        $__profile = s
      end
      
      option [ "-v", "--version" ], :flag, "Print the version and exit" do
        require 'cloud_formation_tool/version'
        puts CloudFormationTool::VERSION
        exit 0
      end
      
      subcommand 'list', "List CloudFormation stacks", ListStacks
      subcommand 'parameters', "List template parameters and their default values", Parameters
      subcommand 'compile', "Compile the specified template", Compile
      subcommand 'monitor', "Monitor recent and upcoming events on the stack", Monitor
      subcommand 'create', "Create a stack from the template or update an existing stack", Create
      subcommand 'status', "Check the current status of a stack", Status
      subcommand 'delete', "Delete an existing stack", Delete
      subcommand 'servers', 'List stack resources', Servers
      subcommand 'recycle', 'Recycle servers in an auto scaling group', Recycle
      subcommand 'scale', 'Set the number of desired servesr in an auto scaling group', Scale
      subcommand 'output', 'Retrieve output values from the stack', Output
    end
  end
end

require 'clamp'
require 'io/console'

module CloudFormationTool
  module CLI
    class Main < Clamp::Command
      
      banner "Compile and deploy CloudFormation templates"
      
      option [ "-r", "--region" ], "REGION", "AWS Region to use", default: 'us-west-1' do |s|
        $__region = s
      end

      subcommand 'list', "List CloudFormation stacks", ListStacks
      subcommand 'parameters', "List template parameters and their default values", Parameters
      subcommand 'compile', "Compile the specified template", Compile
      subcommand 'monitor', "Monitor recent and upcoming events on the stack", Monitor
      subcommand 'create', "Create a stack from the template or update an existing stack", Create
      subcommand 'status', "Check the current status of a stack", Status
      subcommand 'delete', "Delete an existing stack", Delete
      subcommand 'servers', 'List stack resources', Servers
    end
  end
end

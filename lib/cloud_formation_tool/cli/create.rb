require 'uri'
require 'net/http'

module CloudFormationTool
  module CLI
    class Create < Clamp::Command
      include ParamSupport

      parameter 'FILE', 'Template main file'
      parameter '[STACK_NAME]', 'Name of the stack to create. Defaults to directory name'
      
      add_param_options
      
      def execute
        name = stack_name || File.basename(File.dirname(File.expand_path(file)))
        st = CloudFormation::Stack.new(name)
        log "Creating stack #{name}"
        start = Time.now
        log "Created " + st.create(file, get_params).to_s
        st.monitor(start)
        puts st.output
      end
      
    end
  end
end
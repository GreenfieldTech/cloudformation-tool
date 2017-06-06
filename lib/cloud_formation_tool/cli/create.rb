require 'uri'
require 'net/http'

module CloudFormationTool
  module CLI
    class Create < Clamp::Command
      
      parameter 'FILE', 'Template main file'
      parameter '[STACK_NAME]', 'Name of the stack to create. Defaults to directory name'
      
      option [ "-p", "--param" ], "PARAM", [
        "Parameter to use with the cloudformation, of the format Mame=Tag",
        "Use multiple times to set multiple parameters.",
        "See 'parameters' command to list the paramaters supported by the tempalte."
        ].join("\n"), multivalued: true
      option [ "-i", "--import" ], "FILE", "Import parameters from YAML file or HTTP URL.", :attribute_name => :param_file
      option [ "-k", "--import-key" ], "KEY", [
        "When loading parameters from a YAML file, use the specified key to load a named",
        "map from the file, instead of using just the file itself as the parameter map"
        ].join("\n"), :attribute_name => :param_key
      
      def read_param_file(file)
        param_uri = URI(file)
        case param_uri.scheme
        when /^http/
          Net::HTTP.get(param_uri)
        else
          File.read(file)
        end
      end
      
      def get_params
        params = if param_file
          yaml = YAML.load(read_param_file param_file).to_h
          if param_key
            raise "Missing parameter section '#{param_key}' in '#{param_file}'!" unless yaml[param_key].is_a? Hash
            yaml[param_key]
          else
            yaml
          end
        else
          Hash.new
        end
        # allow param_list to override parameters from the param file
        param_list.inject(params) do |h, param|
          k,v = param.split /\s*[=:]\s*/
          h[k] = v
          h
        end
      end
      
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
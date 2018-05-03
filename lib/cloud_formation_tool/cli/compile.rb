module CloudFormationTool
  module CLI
    
    class Compile < Clamp::Command
      include ParamSupport
      
      parameter 'FILE', 'Template main file'
      
      add_param_options
      
      def execute
        if file.end_with? '.init'
          puts CloudInit.new(file).encode(false) # make sure cloud-init files obey AWS user-data restrictions, but are also printable
        else
          tpl = CloudFormation.parse(file)
          params = get_params
          data = tpl.compile(params);
          data['Parameters'].each do |name,param|
            param['Default'] = params[name] if params.has_key? name
          end
          puts data.to_yaml
        end
      end
      
    end
  end
end
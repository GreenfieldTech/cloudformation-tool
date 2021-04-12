module CloudFormationTool
  module CLI
    
    class Compile < Clamp::Command
      include ParamSupport
      
      option "--user-data-size", "SIZE", "Maximum size of VM user data", default: $MAX_USER_DATA_SIZE do |s|
        Integer(s)
      end
      
      parameter 'FILE', 'Template main file'
      
      add_param_options
      
      def execute
      	$MAX_USER_DATA_SIZE = user_data_size
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
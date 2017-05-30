module CloudFormationTool
  module CLI
    
    class Compile < Clamp::Command
      
      parameter 'FILE', 'Template main file'
      
      def execute
        if file.end_with? '.init'
          puts CloudInit.new(file).encode(false) # make sure cloud-init files obey AWS user-data restrictions, but are also printable
        else
          puts CloudFormation.parse(file).to_yaml
  #        raise CloudFormationTool::Errors::AppError.new("not a valid template file. Only .init and .yaml are supported")
        end
      end
      
    end
  end
end
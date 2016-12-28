module CloudFormationTool
  module CLI
    
    class Compile < Clamp::Command
      
      parameter 'FILE', 'Template main file'
      
      def execute
        if file.end_with? '.init'
          puts CloudInit.new(file).compile
        else
          puts CloudFormation.parse(file).to_yaml
  #        raise AppError.new("not a valid template file. Only .init and .yaml are supported")
        end
      end
      
    end
  end
end
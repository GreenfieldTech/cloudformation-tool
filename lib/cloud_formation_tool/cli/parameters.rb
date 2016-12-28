module CloudFormationTool
  module CLI
    
    class Parameters < Clamp::Command
      
      parameter 'FILE', 'Template main file'
      def execute
        donefirst = false
        CloudFormation.parse(file).each do |name, value|
          unless donefirst
            donefirst = true
            puts "---\n"
          end
          puts "#{name}: #{value}"
        end
      end
      
    end
  end
end
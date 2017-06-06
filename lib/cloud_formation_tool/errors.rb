module CloudFormationTool
  module Errors
    
    Autoloaded.module {  }
      
    class BaseError < StandardError; end
    
    class AppError < BaseError; end
    
    class ValidationError < BaseError; end
    
    class StackDoesNotExistError < BaseError; end
    
  end
end
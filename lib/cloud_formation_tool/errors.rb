module CloudFormationTool
  module Errors
    
    Autoloaded.module {  }
      
    class BaseError < StandardError; end
    
    class AppError < BaseError; end
    
    class ValidationError < BaseError; end
    
    class StackDoesNotExistError < BaseError; end
    
    class AuthError < BaseError; end
    
  end
end
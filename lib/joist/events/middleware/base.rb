# frozen_string_literal: true

module Joist
  module Events
    module Middleware
      # Base class for middleware
      #
      # Middleware can intercept and modify message processing.
      # Each middleware must implement #call(message, &block)
      #
      # @example Basic middleware
      #   class LoggingMiddleware < Joist::Events::Middleware::Base
      #     def call(message, &block)
      #       logger.info "Processing #{message.id}"
      #       result = block.call
      #       logger.info "Completed #{message.id}"
      #       result
      #     end
      #   end
      class Base
        # Process a message through this middleware
        #
        # @param message [Message] message being processed
        # @yield The next middleware or final processor
        # @return The result from the block
        # @raise [NotImplementedError] if not overridden
        def call(message, &block)
          raise NotImplementedError, "#{self.class.name} must implement #call"
        end
      end
    end
  end
end

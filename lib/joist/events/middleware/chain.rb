# frozen_string_literal: true

module Joist
  module Events
    module Middleware
      # Middleware chain for processing messages
      #
      # Executes middlewares in order, passing control from one to the next
      #
      # @example Building a chain
      #   chain = Middleware::Chain.new
      #   chain.add(LoggingMiddleware.new)
      #   chain.add(RetryMiddleware.new)
      #   chain.call(message) { |msg| publish(msg) }
      class Chain
        def initialize
          @middlewares = []
        end

        # Add a middleware to the chain
        #
        # @param middleware [Base] middleware instance
        # @return [Chain] self for chaining
        def add(middleware)
          unless middleware.respond_to?(:call)
            raise ArgumentError, "Middleware must respond to #call"
          end
          @middlewares << middleware
          self
        end

        # Execute the middleware chain
        #
        # @param message [Message] message to process
        # @yield Final block to execute after all middlewares
        # @return The result from the final block
        def call(message, &block)
          return block.call if @middlewares.empty?

          # Build nested chain of calls
          chain = @middlewares.reverse.reduce(block) do |next_middleware, current_middleware|
            proc { current_middleware.call(message, &next_middleware) }
          end

          chain.call
        end

        # Check if chain is empty
        #
        # @return [Boolean]
        def empty?
          @middlewares.empty?
        end

        # Get number of middlewares in chain
        #
        # @return [Integer]
        def size
          @middlewares.size
        end

        # Clear all middlewares
        #
        # @return [Chain] self
        def clear
          @middlewares.clear
          self
        end
      end
    end
  end
end

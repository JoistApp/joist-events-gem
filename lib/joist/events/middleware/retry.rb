# frozen_string_literal: true

module Joist
  module Events
    module Middleware
      # Retry middleware for handling transient failures
      #
      # Automatically retries failed operations with exponential backoff.
      #
      # @example Basic usage
      #   middleware = Retry.new(max_attempts: 3, base_delay: 0.5)
      #
      # @example With custom error handler
      #   middleware = Retry.new(
      #     max_attempts: 5,
      #     base_delay: 1.0,
      #     max_delay: 30.0,
      #     on_retry: ->(error, attempt) { logger.warn "Retry #{attempt}: #{error}" }
      #   )
      class Retry < Base
        attr_reader :max_attempts, :base_delay, :max_delay, :backoff_factor, :on_retry

        DEFAULT_RETRIABLE_ERRORS = [
          StandardError # Can be narrowed to specific errors
        ].freeze

        # Create retry middleware
        #
        # @param max_attempts [Integer] maximum number of attempts (including initial)
        # @param base_delay [Float] initial delay in seconds
        # @param max_delay [Float] maximum delay in seconds
        # @param backoff_factor [Float] multiplier for exponential backoff
        # @param retriable_errors [Array<Class>] error classes to retry
        # @param on_retry [Proc] callback on retry (receives error, attempt)
        def initialize(
          max_attempts: 3,
          base_delay: 1.0,
          max_delay: 60.0,
          backoff_factor: 2.0,
          retriable_errors: DEFAULT_RETRIABLE_ERRORS,
          on_retry: nil
        )
          @max_attempts = max_attempts
          @base_delay = base_delay
          @max_delay = max_delay
          @backoff_factor = backoff_factor
          @retriable_errors = retriable_errors
          @on_retry = on_retry

          validate!
        end

        # Process message with retry logic
        #
        # @param message [Message] message to process
        # @yield Block to execute with retry
        # @return Result from block
        # @raise [MiddlewareError] if all retries exhausted
        def call(message, &block)
          attempt = 1

          begin
            block.call
          rescue *@retriable_errors => e
            if attempt < max_attempts
              delay = calculate_delay(attempt)
              log_retry(message, attempt, delay, e)
              @on_retry&.call(e, attempt, message)

              sleep delay
              attempt += 1
              retry
            else
              log_exhausted(message, attempt, e)
              raise MiddlewareError, "Retry exhausted after #{attempt} attempts: #{e.message}"
            end
          end
        end

        private

        def calculate_delay(attempt)
          delay = base_delay * (backoff_factor**(attempt - 1))
          [delay, max_delay].min
        end

        def validate!
          raise ArgumentError, "max_attempts must be >= 1" if max_attempts < 1
          raise ArgumentError, "base_delay must be > 0" if base_delay <= 0
          raise ArgumentError, "max_delay must be > 0" if max_delay <= 0
          raise ArgumentError, "backoff_factor must be >= 1" if backoff_factor < 1
        end

        def log_retry(message, attempt, delay, error)
          Joist::Events.configuration.logger.warn(
            "Retrying message #{message.id} (attempt #{attempt}/#{max_attempts}) " \
            "after #{delay.round(2)}s delay. Error: #{error.class}: #{error.message}"
          )
        end

        def log_exhausted(message, attempt, error)
          Joist::Events.configuration.logger.error(
            "Retry exhausted for message #{message.id} after #{attempt} attempts. " \
            "Final error: #{error.class}: #{error.message}"
          )
        end
      end
    end
  end
end

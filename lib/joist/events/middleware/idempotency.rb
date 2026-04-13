# frozen_string_literal: true

module Joist
  module Events
    module Middleware
      # Idempotency middleware to prevent duplicate message processing
      #
      # Tracks processed message IDs and skips messages that have already been processed.
      # Requires a storage backend to track processed messages.
      #
      # @example With Redis backend
      #   storage = RedisIdempotencyStorage.new(redis: Redis.new)
      #   middleware = Idempotency.new(storage: storage, ttl: 3600)
      #
      # @example With memory backend (testing only)
      #   middleware = Idempotency.new(storage: MemoryIdempotencyStorage.new)
      class Idempotency < Base
        attr_reader :storage, :ttl

        # Create idempotency middleware
        #
        # @param storage [Object] storage backend with #processed?(id) and #mark_processed(id, ttl)
        # @param ttl [Integer] time-to-live for processed message tracking (seconds)
        def initialize(storage:, ttl: 3600)
          @storage = storage
          @ttl = ttl

          validate_storage!
        end

        # Process message with idempotency check
        #
        # @param message [Message] message to process
        # @yield Block to execute if message not already processed
        # @return Result from block, or :duplicate if already processed
        def call(message, &block)
          if storage.processed?(message.id)
            log_duplicate(message)
            return :duplicate
          end

          result = block.call
          # Only mark as processed if the block succeeds
          # If an exception is raised, it will propagate without marking as processed
          storage.mark_processed(message.id, ttl)
          result
        end

        private

        def validate_storage!
          unless storage.respond_to?(:processed?) && storage.respond_to?(:mark_processed)
            raise ArgumentError, "Storage must implement #processed? and #mark_processed"
          end
        end

        def log_duplicate(message)
          Joist::Events.configuration.logger.info(
            "Skipping duplicate message #{message.id} for topic #{message.topic}"
          )
        end
      end

      # Memory-based idempotency storage (for testing only)
      class MemoryIdempotencyStorage
        def initialize
          @processed = {}
        end

        def processed?(message_id)
          @processed.key?(message_id) && @processed[message_id] > Time.now.to_i
        end

        def mark_processed(message_id, ttl)
          @processed[message_id] = Time.now.to_i + ttl
        end

        def clear
          @processed.clear
        end
      end
    end
  end
end

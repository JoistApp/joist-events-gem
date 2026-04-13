# frozen_string_literal: true

require "active_support"
require "active_support/core_ext"
require "logger"

require_relative "joist/events/version"
require_relative "joist/events/configuration"

module Joist
  module Events
    class Error < StandardError; end
    class PublishError < Error; end
    class SubscribeError < Error; end
    class AdapterError < Error; end
    class SerializationError < Error; end
    class MiddlewareError < Error; end

    # Convenience method for publishing
    #
    # @param topic [String] topic name
    # @param message [Hash] message payload
    # @param adapter [Symbol, nil] specific adapter to use (optional)
    def self.publish(topic, message, adapter: nil)
      # TODO: Implement in Phase 2
      raise NotImplementedError, "Publisher interface not yet implemented"
    end

    # Convenience method for subscribing
    #
    # @param topic [String] topic name
    # @param subscriber_name [String] subscriber identifier
    # @param adapter [Symbol, nil] specific adapter to use (optional)
    # @yield [message] block to process messages
    def self.subscribe(topic, subscriber_name, adapter: nil, &block)
      # TODO: Implement in Phase 2
      raise NotImplementedError, "Subscriber interface not yet implemented"
    end
  end
end

# Load components
require_relative "joist/events/message"
require_relative "joist/events/serializers/base"
require_relative "joist/events/serializers/json_serializer"
require_relative "joist/events/middleware/base"
require_relative "joist/events/middleware/chain"
require_relative "joist/events/middleware/idempotency"
require_relative "joist/events/middleware/retry"
require_relative "joist/events/middleware/metrics"
require_relative "joist/events/adapters/base"
require_relative "joist/events/adapters/memory_adapter"
require_relative "joist/events/adapters/gcp_adapter"
require_relative "joist/events/adapters/amazon_mq_adapter"
require_relative "joist/events/publisher"
require_relative "joist/events/subscriber"

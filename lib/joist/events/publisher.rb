# frozen_string_literal: true

module Joist
  module Events
    # Publisher interface for publishing messages to topics
    #
    # @example Basic usage
    #   publisher = Joist::Events::Publisher.new('user-events')
    #   publisher.publish({ user_id: 123, event: 'user.created' })
    #
    # @example Dual-write mode
    #   # Publishes to both GCP and Amazon MQ if configured
    #   publisher.publish(message)
    #
    # @example Specific adapter
    #   publisher = Joist::Events::Publisher.new('user-events', adapter: :amazon_mq)
    #   publisher.publish(message)
    class Publisher
      attr_reader :topic, :adapter_name, :serializer

      # Create a new publisher
      #
      # @param topic [String] topic name
      # @param adapter [Symbol, nil] specific adapter to use (overrides default)
      # @param serializer [Symbol, nil] serializer to use (overrides default)
      def initialize(topic, adapter: nil, serializer: nil)
        @topic = topic
        @adapter_name = adapter || Joist::Events.configuration.default_adapter
        @serializer_name = serializer || Joist::Events.configuration.serializer
        @adapters = build_adapters
        @serializer = build_serializer
        @middleware = build_middleware_chain
      end

      # Publish a message to the topic
      #
      # @param payload [Hash, Message] message payload or Message object
      # @param attributes [Hash] additional metadata
      # @param wait_for_ack [Boolean] wait for broker acknowledgment (default: true)
      # @return [String, Boolean] message ID if wait_for_ack, true otherwise
      # @raise [PublishError] if publish fails
      def publish(payload, attributes: {}, wait_for_ack: true)
        message = ensure_message(payload, attributes)

        # Apply middleware chain
        result = @middleware.call(message) do
          if dual_write?
            publish_dual_write(message, wait_for_ack: wait_for_ack)
          else
            publish_single(message, wait_for_ack: wait_for_ack)
          end
        end

        log_publish(message, result)
        result
      rescue => e
        log_error(message, e)
        raise PublishError, "Failed to publish message: #{e.message}"
      end

      # Publish multiple messages in batch
      #
      # @param messages [Array<Hash, Message>] array of messages
      # @return [Integer] number of messages published
      def publish_batch(messages)
        messages.map { |msg| publish(msg) }.count(true)
      end

      # Check if dual-write mode is enabled
      #
      # @return [Boolean]
      def dual_write?
        Joist::Events.configuration.dual_write?
      end

      private

      def build_adapters
        if dual_write?
          # Build all dual-write adapters
          Joist::Events.configuration.dual_write_adapters.map do |adapter_name|
            build_adapter(adapter_name)
          end
        else
          # Build single adapter
          [build_adapter(@adapter_name)]
        end
      end

      def build_adapter(adapter_name)
        adapter_config = Joist::Events.configuration.adapters[adapter_name]

        unless adapter_config
          raise ArgumentError, "Adapter #{adapter_name} not registered"
        end

        case adapter_name
        when :gcp
          Adapters::GcpAdapter.new(adapter_config)
        when :amazon_mq
          Adapters::AmazonMqAdapter.new(adapter_config)
        when :memory
          Adapters::MemoryAdapter.new(adapter_config)
        else
          raise ArgumentError, "Unknown adapter type: #{adapter_name}"
        end
      end

      def build_serializer
        case @serializer_name
        when :json
          Serializers::JsonSerializer.new
        else
          raise ArgumentError, "Unknown serializer: #{@serializer_name}"
        end
      end

      def build_middleware_chain
        Middleware::Chain.new

        # Build middlewares from configuration
        # TODO: In future, allow per-publisher middleware configuration
        # For now, return empty chain (middlewares can be added via configuration)
      end

      def ensure_message(payload, attributes)
        return payload if payload.is_a?(Message)

        Message.new(
          topic: @topic,
          payload: payload,
          attributes: attributes
        )
      end

      def publish_single(message, wait_for_ack:)
        adapter = @adapters.first
        serialized = @serializer.serialize(message)
        adapter.publish(@topic, serialized, wait_for_ack: wait_for_ack)
      end

      def publish_dual_write(message, wait_for_ack:)
        serialized = @serializer.serialize(message)
        results = @adapters.map do |adapter|
          adapter.publish(@topic, serialized, wait_for_ack: wait_for_ack)
        end
        # For dual-write, return true if all succeeded, false otherwise
        # (individual message IDs not meaningful when writing to multiple brokers)
        results.all? { |r| r }
      end

      def log_publish(message, result)
        Joist::Events.configuration.logger.debug(
          "Published message #{message.id} to #{@topic} (result: #{result})"
        )
      end

      def log_error(message, error)
        Joist::Events.configuration.logger.error(
          "Failed to publish message #{message&.id} to #{@topic}: #{error.message}"
        )
      end
    end
  end
end

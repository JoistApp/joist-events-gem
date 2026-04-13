# frozen_string_literal: true

module Joist
  module Events
    # Base class for event subscribers
    #
    # @example Define a subscriber
    #   class UserCreatedSubscriber < Joist::Events::Subscriber
    #     topic 'user-events'
    #     subscriber_name 'user-service'
    #
    #     def consume!(message)
    #       user_id = message.payload['user_id']
    #       puts "User #{user_id} created"
    #     end
    #   end
    #
    # @example Start subscriber
    #   subscriber = UserCreatedSubscriber.new
    #   subscriber.subscribe!
    #
    # @example Configure adapter-specific options
    #   subscriber = UserCreatedSubscriber.new(
    #     prefetch: 10,
    #     manual_ack: true
    #   )
    class Subscriber
      class << self
        # Set the topic to subscribe to
        #
        # @param name [String] topic name
        def topic(name = nil)
          if name
            @topic_name = name
          else
            @topic_name
          end
        end

        # Get the topic name
        attr_reader :topic_name

        # Set the subscriber name
        #
        # @param name [String] subscriber identifier
        def subscriber_name(name = nil)
          if name
            @subscriber_name = name
          else
            @subscriber_name
          end
        end
      end

      attr_reader :topic, :name, :adapter, :options

      # Create a new subscriber
      #
      # @param options [Hash] subscriber options
      # @option options [String] :topic Topic name (overrides class-level topic)
      # @option options [String] :name Subscriber name (overrides class-level subscriber_name)
      # @option options [Symbol] :adapter Adapter to use (overrides default)
      # Additional options are passed through to the adapter (e.g., prefetch, manual_ack)
      def initialize(options = {})
        @topic = options[:topic] || self.class.topic_name
        @name = options[:name] || self.class.subscriber_name
        @options = options
        @running = false

        validate!

        @adapter_name = options[:adapter] || Joist::Events.configuration.default_adapter
        @serializer_name = options[:serializer] || Joist::Events.configuration.serializer
        @adapter = build_adapter
        @serializer = build_serializer
        @middleware = build_middleware_chain
      end

      # Start subscribing to messages
      #
      # This method blocks and continuously processes messages
      def subscribe!
        return if @running

        @running = true
        log_start

        @adapter.subscribe(@topic, @name, @options) do |raw_message|
          process_message(raw_message)
        end
      rescue => e
        log_error("Subscription error", e)
        raise SubscribeError, "Failed to subscribe: #{e.message}"
      ensure
        @running = false
      end

      # Stop subscribing
      def stop!
        @running = false
        @adapter.stop if @adapter.respond_to?(:stop)
        log_stop
      end

      # Check if subscriber is running
      #
      # @return [Boolean]
      def running?
        @running
      end

      # Process a message (must be implemented by subclass)
      #
      # @param message [Message] message to process
      # @raise [NotImplementedError] if not overridden
      def consume!(message)
        raise NotImplementedError, "#{self.class.name} must implement #consume!"
      end

      private

      def process_message(raw_message)
        message = parse_message(raw_message)

        # Apply middleware chain
        @middleware.call(message) do
          consume!(message)
        end

        log_consumed(message)
      rescue => e
        log_error("Failed to process message", e, message)
        raise
      end

      def parse_message(raw_message)
        if raw_message.is_a?(Message)
          raw_message
        elsif raw_message.is_a?(String)
          @serializer.deserialize(raw_message)
        elsif raw_message.is_a?(Hash)
          Message.from_h(raw_message)
        else
          raise SubscribeError, "Unknown message format: #{raw_message.class}"
        end
      end

      def build_adapter
        adapter_config = Joist::Events.configuration.adapters[@adapter_name]

        unless adapter_config
          raise ArgumentError, "Adapter #{@adapter_name} not registered"
        end

        case @adapter_name
        when :gcp
          Adapters::GcpAdapter.new(adapter_config)
        when :amazon_mq
          Adapters::AmazonMqAdapter.new(adapter_config)
        when :memory
          Adapters::MemoryAdapter.new(adapter_config)
        else
          raise ArgumentError, "Unknown adapter type: #{@adapter_name}"
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
        # TODO: In future, allow per-subscriber middleware configuration
        # For now, return empty chain (middlewares can be added via configuration)
      end

      def validate!
        raise ArgumentError, "topic must be set" if @topic.nil? || @topic.empty?
        raise ArgumentError, "subscriber_name must be set" if @name.nil? || @name.empty?
      end

      def log_start
        Joist::Events.configuration.logger.info(
          "Starting subscriber #{@name} for topic #{@topic} (adapter: #{@adapter_name})"
        )
      end

      def log_stop
        Joist::Events.configuration.logger.info(
          "Stopped subscriber #{@name} for topic #{@topic}"
        )
      end

      def log_consumed(message)
        Joist::Events.configuration.logger.debug(
          "Consumed message #{message.id} from #{@topic}"
        )
      end

      def log_error(context, error, message = nil)
        msg_id = message&.id || "unknown"
        Joist::Events.configuration.logger.error(
          "#{context} (message: #{msg_id}): #{error.message}\n#{error.backtrace&.first(5)&.join("\n")}"
        )
      end
    end
  end
end

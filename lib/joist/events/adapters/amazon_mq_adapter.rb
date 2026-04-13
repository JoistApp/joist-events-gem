# frozen_string_literal: true

require "bunny"

module Joist
  module Events
    module Adapters
      # Amazon MQ (RabbitMQ) adapter
      #
      # Provides RabbitMQ/Amazon MQ support using the Bunny gem.
      #
      # @example Basic usage
      #   adapter = AmazonMqAdapter.new(
      #     host: "b-xxx.mq.us-east-1.amazonaws.com",
      #     port: 5671,
      #     username: "admin",
      #     password: "password",
      #     tls: true
      #   )
      #   adapter.publish("user-events", '{"user_id": 123}')
      class AmazonMqAdapter < Base
        attr_reader :connection, :channel

        # Create Amazon MQ adapter
        #
        # @param options [Hash] adapter options
        # @option options [String] :host RabbitMQ host (required)
        # @option options [Integer] :port RabbitMQ port (default: 5672, 5671 for TLS)
        # @option options [String] :username Username (required)
        # @option options [String] :password Password (required)
        # @option options [String] :vhost Virtual host (default: "/")
        # @option options [Boolean] :tls Use TLS (default: false)
        # @option options [String] :exchange_type Exchange type (default: "topic")
        def initialize(options = {})
          super
          @host = options[:host]
          @port = options[:port] || (options[:tls] ? 5671 : 5672)
          @username = options[:username]
          @password = options[:password]
          @vhost = options[:vhost] || "/"
          @tls = options[:tls] || false
          @exchange_type = options[:exchange_type] || "topic"

          @connection = nil
          @channel = nil
          @exchanges = {}
          @subscriptions = []
        end

        # Publish a message to a topic
        #
        # @param topic [String] topic name (becomes exchange name)
        # @param message [String] serialized message
        # @param options [Hash] publish options
        # @option options [Boolean] :wait_for_ack Wait for broker acknowledgment (default: true)
        # @return [String, Boolean] delivery tag if wait_for_ack, true otherwise
        # @raise [AdapterError] if publish fails
        def publish(topic, message, options = {})
          wait_for_ack = options.fetch(:wait_for_ack, true)

          ensure_connected!
          exchange = ensure_exchange(topic)

          # Enable publisher confirms if waiting for ack
          if wait_for_ack && @channel
            @channel.confirm_select unless @channel.using_publisher_confirmations?
          end

          exchange.publish(
            message,
            routing_key: topic,
            persistent: true,
            content_type: "application/json"
          )

          if wait_for_ack && @channel
            # Wait for confirmation from broker
            success = @channel.wait_for_confirms
            raise AdapterError, "Message not confirmed by broker" unless success
            # Return a synthetic message ID (RabbitMQ doesn't provide one automatically)
            "#{topic}-#{Time.now.to_i}-#{rand(10000)}"
          else
            true
          end
        rescue Bunny::Exception => e
          raise AdapterError, "RabbitMQ publish error: #{e.message}"
        end

        # Subscribe to a topic
        #
        # @param topic [String] topic name (becomes exchange name)
        # @param subscriber_name [String] subscriber identifier (becomes queue name)
        # @param options [Hash] subscription options
        # @option options [Integer] :prefetch Number of messages to prefetch (default: 10)
        # @option options [Boolean] :manual_ack Manual acknowledgment (default: false)
        # @yield [String] block called for each message
        # @raise [AdapterError] if subscribe fails
        def subscribe(topic, subscriber_name, options = {}, &block)
          raise ArgumentError, "Block required for subscribe" unless block_given?

          ensure_connected!
          exchange = ensure_exchange(topic)

          # Create queue for this subscriber
          queue_name = build_queue_name(topic, subscriber_name)
          queue = @channel.queue(queue_name, durable: true, auto_delete: false)

          # Bind queue to exchange
          queue.bind(exchange, routing_key: topic)

          # Set prefetch
          prefetch = options[:prefetch] || 10
          @channel.prefetch(prefetch)

          # Subscribe to queue
          manual_ack = options[:manual_ack] || false

          consumer = queue.subscribe(manual_ack: manual_ack, block: true) do |delivery_info, properties, payload|
            block.call(payload)

            # Acknowledge message if manual ack enabled
            @channel.ack(delivery_info.delivery_tag) if manual_ack
          rescue => e
            Joist::Events.configuration.logger.error(
              "Error processing message: #{e.message}"
            )

            # Reject and requeue on error if manual ack enabled
            @channel.nack(delivery_info.delivery_tag, false, true) if manual_ack
            raise
          end

          @subscriptions << consumer
        rescue Bunny::Exception => e
          raise AdapterError, "RabbitMQ subscribe error: #{e.message}"
        end

        # Stop the adapter
        def stop
          @subscriptions.each do |consumer|
            consumer.cancel if consumer.respond_to?(:cancel)
          end
          @subscriptions.clear

          @channel&.close
          @connection&.close
        rescue Bunny::Exception => e
          Joist::Events.configuration.logger.error(
            "Error stopping RabbitMQ adapter: #{e.message}"
          )
        end

        # Check if adapter is healthy
        #
        # @return [Boolean] true if connected to RabbitMQ
        def healthy?
          return false unless @connection && @channel
          @connection.open? && @channel.open?
        rescue
          false
        end

        private

        def validate_options!
          unless @options[:host]
            raise ArgumentError, "host is required for Amazon MQ adapter"
          end
          unless @options[:username]
            raise ArgumentError, "username is required for Amazon MQ adapter"
          end
          unless @options[:password]
            raise ArgumentError, "password is required for Amazon MQ adapter"
          end
        end

        def ensure_connected!
          return if @connection&.open?

          connection_options = {
            host: @host,
            port: @port,
            username: @username,
            password: @password,
            vhost: @vhost,
            tls: @tls,
            automatically_recover: true,
            network_recovery_interval: 5
          }

          @connection = Bunny.new(connection_options)
          @connection.start
          @channel = @connection.create_channel

          Joist::Events.configuration.logger.info(
            "Connected to RabbitMQ at #{@host}:#{@port}"
          )
        rescue Bunny::Exception => e
          raise AdapterError, "Failed to connect to RabbitMQ: #{e.message}"
        end

        def ensure_exchange(topic)
          return @exchanges[topic] if @exchanges[topic]

          ensure_connected!

          @exchanges[topic] = @channel.exchange(
            topic,
            type: @exchange_type,
            durable: true,
            auto_delete: false
          )
        end

        def build_queue_name(topic, subscriber_name)
          # Format: topic.subscriber_name
          "#{topic}.#{subscriber_name}"
        end
      end
    end
  end
end

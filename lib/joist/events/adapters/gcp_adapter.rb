# frozen_string_literal: true

require "google/cloud/pubsub"

module Joist
  module Events
    module Adapters
      # Google Cloud Pub/Sub adapter
      #
      # Wraps Google Cloud Pub/Sub for publishing and subscribing to messages.
      #
      # @example Basic usage
      #   adapter = GcpAdapter.new(project_id: "my-project")
      #   adapter.publish("user-events", '{"user_id": 123}')
      #
      # @example With credentials
      #   adapter = GcpAdapter.new(
      #     project_id: "my-project",
      #     credentials: "/path/to/credentials.json"
      #   )
      class GcpAdapter < Base
        attr_reader :project_id, :pubsub

        # Create GCP adapter
        #
        # @param options [Hash] adapter options
        # @option options [String] :project_id GCP project ID (required)
        # @option options [String] :credentials Path to credentials file
        # @option options [String] :emulator_host Emulator host for testing
        def initialize(options = {})
          super
          @project_id = options[:project_id]
          @credentials = options[:credentials]
          @emulator_host = options[:emulator_host]
          @pubsub = build_pubsub_client
        end

        # Publish a message to a topic
        #
        # @param topic [String] topic name
        # @param message [String] serialized message
        # @param options [Hash] publish options
        # @option options [Boolean] :wait_for_ack Wait for broker acknowledgment (default: true)
        # @return [String, Boolean] message ID if wait_for_ack, true otherwise
        # @raise [AdapterError] if publish fails
        def publish(topic, message, options = {})
          wait_for_ack = options.fetch(:wait_for_ack, true)

          gcp_topic = @pubsub.topic(topic, skip_lookup: true)

          unless gcp_topic
            raise AdapterError, "Topic #{topic} not found in project #{@project_id}"
          end

          result = gcp_topic.publish(message)

          if result.nil?
            raise AdapterError, "Failed to publish message to topic #{topic}"
          end

          # GCP publish returns a PublishResult object with message_id
          # The message is already acknowledged by the time publish returns
          if wait_for_ack
            # Try to get message_id from the result
            # Different versions of the gem may have different method names
            message_id = result.respond_to?(:message_id) ? result.message_id : nil
            message_id || true
          else
            true
          end
        rescue Google::Cloud::Error => e
          raise AdapterError, "GCP Pub/Sub error: #{e.message}"
        end

        # Subscribe to a topic
        #
        # @param topic [String] topic name
        # @param subscriber_name [String] subscriber identifier
        # @param options [Hash] subscription options (passed through to GCP Pub/Sub)
        # @yield [String] block called for each message
        # @raise [AdapterError] if subscribe fails
        def subscribe(topic, subscriber_name, options = {}, &block)
          raise ArgumentError, "Block required for subscribe" unless block_given?

          subscription_name = build_subscription_name(topic, subscriber_name)
          subscription = ensure_subscription(topic, subscription_name)

          # Build listen options from provided configuration
          listen_options = {}
          listen_options[:threads] = {callback: options[:threads]} if options[:threads]
          listen_options[:streams] = options[:streams] if options[:streams]

          @subscriber = subscription.listen(**listen_options) do |received_message|
            # Pass the message data (string) to the block
            block.call(received_message.data)

            # Acknowledge the message
            received_message.acknowledge!
          rescue => e
            # Log error but don't crash subscriber
            Joist::Events.configuration.logger.error(
              "Error processing message #{received_message.message_id}: #{e.message}"
            )
            # Optionally: nack message for retry
            # received_message.nack!
            raise
          end

          @subscriber.start
          @subscriber.wait!
        rescue Google::Cloud::Error => e
          raise AdapterError, "GCP Pub/Sub subscribe error: #{e.message}"
        end

        # Stop the subscriber
        def stop
          @subscriber&.stop
        end

        # Check if adapter is healthy
        #
        # @return [Boolean] true if can connect to GCP
        def healthy?
          @pubsub.project_id.present?
        rescue
          false
        end

        private

        def validate_options!
          unless @options[:project_id]
            raise ArgumentError, "project_id is required for GCP adapter"
          end
        end

        def build_pubsub_client
          client_options = {project_id: @project_id}
          client_options[:credentials] = @credentials if @credentials
          client_options[:emulator_host] = @emulator_host if @emulator_host

          Google::Cloud::PubSub.new(**client_options)
        end

        def build_subscription_name(topic, subscriber_name)
          # Format: topic-subscriber_name
          "#{topic}-#{subscriber_name}"
        end

        def ensure_subscription(topic, subscription_name)
          subscription = @pubsub.subscription(subscription_name)

          unless subscription
            # Create subscription if it doesn't exist
            gcp_topic = @pubsub.topic(topic)
            unless gcp_topic
              raise AdapterError, "Topic #{topic} does not exist in project #{@project_id}"
            end

            subscription = gcp_topic.subscribe(subscription_name)
            Joist::Events.configuration.logger.info(
              "Created subscription #{subscription_name} for topic #{topic}"
            )
          end

          subscription
        end
      end
    end
  end
end

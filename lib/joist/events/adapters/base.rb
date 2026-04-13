# frozen_string_literal: true

module Joist
  module Events
    module Adapters
      # Base class for message adapters
      #
      # Adapters provide the transport layer for publishing and subscribing to messages.
      # Each adapter must implement #publish and #subscribe methods.
      #
      # @example Basic adapter
      #   class CustomAdapter < Joist::Events::Adapters::Base
      #     def publish(topic, message)
      #       # Send message to topic
      #       true
      #     end
      #
      #     def subscribe(topic, subscriber_name, options = {}, &block)
      #       # Receive messages and call block
      #     end
      #   end
      class Base
        attr_reader :options

        # Create a new adapter
        #
        # @param options [Hash] adapter-specific options
        def initialize(options = {})
          @options = options
          validate_options!
        end

        # Publish a message to a topic
        #
        # @param topic [String] topic name
        # @param message [String] serialized message
        # @param options [Hash] publish options
        # @option options [Boolean] :wait_for_ack Wait for broker acknowledgment (default: true)
        # @return [String, Boolean] message ID if acknowledged, true otherwise
        # @raise [AdapterError] if publish fails
        # @raise [NotImplementedError] if not overridden
        def publish(topic, message, options = {})
          raise NotImplementedError, "#{self.class.name} must implement #publish"
        end

        # Subscribe to a topic
        #
        # @param topic [String] topic name
        # @param subscriber_name [String] subscriber identifier
        # @param options [Hash] subscription options
        # @yield [String] block called for each message (receives serialized message)
        # @raise [AdapterError] if subscribe fails
        # @raise [NotImplementedError] if not overridden
        def subscribe(topic, subscriber_name, options = {}, &block)
          raise NotImplementedError, "#{self.class.name} must implement #subscribe"
        end

        # Stop the adapter (optional)
        #
        # Called when subscriber stops. Override if cleanup is needed.
        def stop
          # Default: no-op
        end

        # Check if adapter is healthy (optional)
        #
        # @return [Boolean] true if adapter can communicate with backend
        def healthy?
          true
        end

        private

        # Validate adapter options
        #
        # Override in subclasses to enforce required options
        def validate_options!
          # Default: no validation
        end
      end
    end
  end
end

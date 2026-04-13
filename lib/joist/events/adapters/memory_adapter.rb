# frozen_string_literal: true

module Joist
  module Events
    module Adapters
      # In-memory adapter for testing
      #
      # Stores messages in memory and allows synchronous processing.
      # Useful for testing without external dependencies.
      #
      # @example Basic usage
      #   adapter = MemoryAdapter.new
      #   adapter.publish("user-events", '{"user_id": 123}')
      #   adapter.messages["user-events"] # => [serialized messages]
      class MemoryAdapter < Base
        attr_reader :messages, :subscribers

        def initialize(options = {})
          super
          @messages = Hash.new { |h, k| h[k] = [] }
          @subscribers = Hash.new { |h, k| h[k] = [] }
          @running = false
          @mutex = Mutex.new
        end

        # Publish a message to a topic
        #
        # @param topic [String] topic name
        # @param message [String] serialized message
        # @param options [Hash] publish options
        # @option options [Boolean] :wait_for_ack Wait for acknowledgment (default: true)
        # @return [String, Boolean] message ID if wait_for_ack, true otherwise
        def publish(topic, message, options = {})
          wait_for_ack = options.fetch(:wait_for_ack, true)

          @mutex.synchronize do
            @messages[topic] << message

            # Immediately deliver to active subscribers
            @subscribers[topic].each do |subscriber|
              subscriber[:block].call(message)
            rescue => e
              # Log but don't fail publish
              Joist::Events.configuration.logger.error(
                "Memory adapter: Error delivering to subscriber #{subscriber[:name]}: #{e.message}"
              )
            end
          end

          if wait_for_ack
            # Return a synthetic message ID
            "memory-#{topic}-#{Time.now.to_i}-#{rand(10000)}"
          else
            true
          end
        end

        # Subscribe to a topic
        #
        # @param topic [String] topic name
        # @param subscriber_name [String] subscriber identifier
        # @param options [Hash] subscription options
        # @yield [String] block called for each message
        def subscribe(topic, subscriber_name, options = {}, &block)
          raise ArgumentError, "Block required for subscribe" unless block_given?

          @mutex.synchronize do
            @subscribers[topic] << {
              name: subscriber_name,
              block: block,
              options: options
            }
          end

          # Keep subscriber active
          # For testing, we rely on immediate delivery in publish
          sleep 0.01 while @running
        end

        # Stop the adapter
        def stop
          @running = false
        end

        # Start processing (for async testing)
        def start
          @running = true
        end

        # Get messages for a topic
        #
        # @param topic [String] topic name
        # @return [Array<String>] array of serialized messages
        def messages_for(topic)
          @mutex.synchronize { @messages[topic].dup }
        end

        # Get subscriber count for a topic
        #
        # @param topic [String] topic name
        # @return [Integer] number of subscribers
        def subscriber_count(topic)
          @mutex.synchronize { @subscribers[topic].size }
        end

        # Clear all messages
        def clear_messages
          @mutex.synchronize { @messages.clear }
        end

        # Clear all subscribers
        def clear_subscribers
          @mutex.synchronize { @subscribers.clear }
        end

        # Clear everything
        def reset
          @mutex.synchronize do
            @messages.clear
            @subscribers.clear
            @running = false
          end
        end

        # Check if adapter is running
        #
        # @return [Boolean]
        def running?
          @running
        end
      end
    end
  end
end

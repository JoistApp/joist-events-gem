# frozen_string_literal: true

require "securerandom"

module Joist
  module Events
    # Represents a message to be published or consumed
    #
    # @example Create a message
    #   message = Joist::Events::Message.new(
    #     topic: "user-events",
    #     payload: { user_id: 123, event: "user.created" }
    #   )
    #
    # @example Access metadata
    #   message.id         # => "uuid"
    #   message.timestamp  # => Time object
    #   message.topic      # => "user-events"
    class Message
      attr_reader :id, :topic, :payload, :timestamp, :attributes

      # Create a new message
      #
      # @param topic [String] topic name
      # @param payload [Hash] message payload
      # @param id [String, nil] message ID (auto-generated if nil)
      # @param timestamp [Time, nil] message timestamp (defaults to now)
      # @param attributes [Hash] additional metadata
      def initialize(topic:, payload:, id: nil, timestamp: nil, attributes: {})
        @id = id || SecureRandom.uuid
        @topic = topic
        @payload = payload
        @timestamp = timestamp || Time.now.utc
        @attributes = attributes || {}

        validate!
      end

      # Serialize message to hash
      #
      # @return [Hash]
      def to_h
        {
          id: @id,
          topic: @topic,
          payload: @payload,
          timestamp: @timestamp.iso8601,
          attributes: @attributes
        }
      end

      # Serialize message to JSON
      #
      # @return [String]
      def to_json(*_args)
        MultiJson.dump(to_h)
      end

      # Create message from hash
      #
      # @param hash [Hash] message data
      # @return [Message]
      def self.from_h(hash)
        new(
          topic: hash[:topic] || hash["topic"],
          payload: hash[:payload] || hash["payload"],
          id: hash[:id] || hash["id"],
          timestamp: parse_timestamp(hash[:timestamp] || hash["timestamp"]),
          attributes: hash[:attributes] || hash["attributes"] || {}
        )
      end

      # Create message from JSON
      #
      # @param json [String] JSON string
      # @return [Message]
      def self.from_json(json)
        hash = MultiJson.load(json, symbolize_keys: true)
        from_h(hash)
      end

      # Check if message is equal to another
      #
      # @param other [Message]
      # @return [Boolean]
      def ==(other)
        return false unless other.is_a?(Message)

        id == other.id &&
          topic == other.topic &&
          payload == other.payload
      end

      alias_method :eql?, :==

      def hash
        [id, topic, payload].hash
      end

      class << self
        private

        def parse_timestamp(timestamp)
          return timestamp if timestamp.is_a?(Time)
          return Time.parse(timestamp) if timestamp.is_a?(String)
          Time.now.utc
        end
      end

      private

      def validate!
        raise ArgumentError, "topic is required" if @topic.nil? || @topic.empty?
        raise ArgumentError, "payload must be a Hash" unless @payload.is_a?(Hash)
        raise ArgumentError, "timestamp must be a Time object" unless @timestamp.is_a?(Time)
      end
    end
  end
end

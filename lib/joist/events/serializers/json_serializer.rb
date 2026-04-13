# frozen_string_literal: true

require "multi_json"

module Joist
  module Events
    module Serializers
      # JSON serializer for messages
      #
      # Converts Message objects to/from JSON format
      class JsonSerializer < Base
        # Serialize a message to JSON
        #
        # @param message [Message] message to serialize
        # @return [String] JSON string
        def serialize(message)
          MultiJson.dump(message.to_h)
        end

        # Deserialize JSON to a Message
        #
        # @param data [String] JSON string
        # @return [Message] deserialized message
        def deserialize(data)
          hash = MultiJson.load(data, symbolize_keys: true)
          Message.from_h(hash)
        end
      end
    end
  end
end

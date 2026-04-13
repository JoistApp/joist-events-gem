# frozen_string_literal: true

module Joist
  module Events
    module Serializers
      # Base class for message serializers
      #
      # Serializers convert Message objects to wire format and back
      class Base
        # Serialize a message to wire format
        #
        # @param message [Message] message to serialize
        # @return [String] serialized message
        # @raise [NotImplementedError] if not implemented by subclass
        def serialize(message)
          raise NotImplementedError, "#{self.class.name} must implement #serialize"
        end

        # Deserialize wire format to a Message
        #
        # @param data [String] serialized message data
        # @return [Message] deserialized message
        # @raise [NotImplementedError] if not implemented by subclass
        def deserialize(data)
          raise NotImplementedError, "#{self.class.name} must implement #deserialize"
        end
      end
    end
  end
end

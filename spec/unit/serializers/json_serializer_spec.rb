# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Serializers::JsonSerializer do
  let(:serializer) { described_class.new }

  describe "#serialize" do
    it "serializes a message to JSON" do
      message = Joist::Events::Message.new(
        topic: "user-events",
        payload: {user_id: 123, event: "user.created"},
        id: "msg-1",
        attributes: {priority: "high"}
      )

      json = serializer.serialize(message)
      parsed = MultiJson.load(json, symbolize_keys: true)

      expect(parsed[:id]).to eq("msg-1")
      expect(parsed[:topic]).to eq("user-events")
      expect(parsed[:payload]).to eq(user_id: 123, event: "user.created")
      expect(parsed[:attributes]).to eq(priority: "high")
      expect(parsed[:timestamp]).to be_a(String)
    end

    it "handles messages with empty attributes" do
      message = Joist::Events::Message.new(
        topic: "test",
        payload: {data: "value"}
      )

      json = serializer.serialize(message)
      parsed = MultiJson.load(json, symbolize_keys: true)

      expect(parsed[:attributes]).to eq({})
    end

    it "serializes timestamp as ISO8601" do
      time = Time.parse("2026-04-09 12:00:00 UTC")
      message = Joist::Events::Message.new(
        topic: "test",
        payload: {},
        timestamp: time
      )

      json = serializer.serialize(message)
      parsed = MultiJson.load(json, symbolize_keys: true)

      expect(parsed[:timestamp]).to eq("2026-04-09T12:00:00Z")
    end

    it "handles nested payload structures" do
      message = Joist::Events::Message.new(
        topic: "test",
        payload: {
          user: {
            id: 123,
            name: "Test User",
            tags: ["admin", "developer"]
          }
        }
      )

      json = serializer.serialize(message)
      parsed = MultiJson.load(json, symbolize_keys: true)

      expect(parsed[:payload][:user][:tags]).to eq(["admin", "developer"])
    end
  end

  describe "#deserialize" do
    it "deserializes JSON to a Message" do
      json = '{"id":"msg-1","topic":"user-events","payload":{"user_id":123},"timestamp":"2026-04-09T12:00:00Z","attributes":{"priority":"high"}}'

      message = serializer.deserialize(json)

      expect(message).to be_a(Joist::Events::Message)
      expect(message.id).to eq("msg-1")
      expect(message.topic).to eq("user-events")
      expect(message.payload).to eq(user_id: 123)
      expect(message.attributes).to eq(priority: "high")
      expect(message.timestamp).to eq(Time.parse("2026-04-09 12:00:00 UTC"))
    end

    it "handles JSON with string keys" do
      json = '{"id":"msg-1","topic":"test","payload":{"key":"value"},"timestamp":"2026-04-09T12:00:00Z","attributes":{}}'

      message = serializer.deserialize(json)

      expect(message.topic).to eq("test")
      expect(message.payload).to eq(key: "value")
    end

    it "handles missing attributes in JSON" do
      json = '{"id":"msg-1","topic":"test","payload":{},"timestamp":"2026-04-09T12:00:00Z"}'

      message = serializer.deserialize(json)

      expect(message.attributes).to eq({})
    end

    it "handles nested payload structures" do
      json = '{"id":"msg-1","topic":"test","payload":{"user":{"id":123,"tags":["admin"]}},"timestamp":"2026-04-09T12:00:00Z","attributes":{}}'

      message = serializer.deserialize(json)

      expect(message.payload[:user][:tags]).to eq(["admin"])
    end

    it "raises error for invalid JSON" do
      expect {
        serializer.deserialize("not valid json")
      }.to raise_error(MultiJson::ParseError)
    end
  end

  describe "round-trip serialization" do
    it "maintains data integrity through serialize/deserialize cycle" do
      original = Joist::Events::Message.new(
        topic: "user-events",
        payload: {
          user_id: 123,
          metadata: {
            source: "web",
            tags: ["important", "urgent"]
          }
        },
        id: "msg-1",
        attributes: {priority: "high"}
      )

      json = serializer.serialize(original)
      restored = serializer.deserialize(json)

      expect(restored.id).to eq(original.id)
      expect(restored.topic).to eq(original.topic)
      expect(restored.payload).to eq(original.payload)
      expect(restored.attributes).to eq(original.attributes)
      expect(restored.timestamp.to_i).to eq(original.timestamp.to_i)
    end
  end
end

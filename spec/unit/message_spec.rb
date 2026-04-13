# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Message do
  describe ".new" do
    it "creates a message with required fields" do
      message = described_class.new(
        topic: "user-events",
        payload: {user_id: 123, event: "user.created"}
      )

      expect(message.topic).to eq("user-events")
      expect(message.payload).to eq(user_id: 123, event: "user.created")
      expect(message.id).to be_a(String)
      expect(message.timestamp).to be_a(Time)
      expect(message.attributes).to eq({})
    end

    it "accepts optional id" do
      message = described_class.new(
        topic: "user-events",
        payload: {user_id: 123},
        id: "custom-id"
      )

      expect(message.id).to eq("custom-id")
    end

    it "accepts optional timestamp" do
      time = Time.parse("2026-04-09 12:00:00 UTC")
      message = described_class.new(
        topic: "user-events",
        payload: {user_id: 123},
        timestamp: time
      )

      expect(message.timestamp).to eq(time)
    end

    it "accepts optional attributes" do
      message = described_class.new(
        topic: "user-events",
        payload: {user_id: 123},
        attributes: {priority: "high"}
      )

      expect(message.attributes).to eq(priority: "high")
    end

    it "auto-generates UUID if id not provided" do
      message = described_class.new(topic: "test", payload: {})
      expect(message.id).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end

    it "defaults timestamp to current time" do
      before_time = Time.now.utc
      message = described_class.new(topic: "test", payload: {})
      after_time = Time.now.utc

      expect(message.timestamp).to be_between(before_time, after_time)
    end

    it "raises error if topic is nil" do
      expect {
        described_class.new(topic: nil, payload: {})
      }.to raise_error(ArgumentError, "topic is required")
    end

    it "raises error if topic is empty" do
      expect {
        described_class.new(topic: "", payload: {})
      }.to raise_error(ArgumentError, "topic is required")
    end

    it "raises error if payload is not a Hash" do
      expect {
        described_class.new(topic: "test", payload: "not a hash")
      }.to raise_error(ArgumentError, "payload must be a Hash")
    end

    it "raises error if timestamp is not a Time object" do
      expect {
        described_class.new(topic: "test", payload: {}, timestamp: "invalid")
      }.to raise_error(ArgumentError, "timestamp must be a Time object")
    end
  end

  describe "#to_h" do
    it "converts message to hash" do
      time = Time.parse("2026-04-09 12:00:00 UTC")
      message = described_class.new(
        topic: "user-events",
        payload: {user_id: 123},
        id: "msg-1",
        timestamp: time,
        attributes: {priority: "high"}
      )

      hash = message.to_h

      expect(hash).to eq(
        id: "msg-1",
        topic: "user-events",
        payload: {user_id: 123},
        timestamp: "2026-04-09T12:00:00Z",
        attributes: {priority: "high"}
      )
    end

    it "serializes timestamp as ISO8601" do
      time = Time.parse("2026-04-09 12:00:00 UTC")
      message = described_class.new(topic: "test", payload: {}, timestamp: time)

      expect(message.to_h[:timestamp]).to eq("2026-04-09T12:00:00Z")
    end
  end

  describe "#to_json" do
    it "converts message to JSON" do
      message = described_class.new(
        topic: "user-events",
        payload: {user_id: 123},
        id: "msg-1"
      )

      json = message.to_json
      parsed = MultiJson.load(json, symbolize_keys: true)

      expect(parsed[:id]).to eq("msg-1")
      expect(parsed[:topic]).to eq("user-events")
      expect(parsed[:payload]).to eq(user_id: 123)
    end
  end

  describe ".from_h" do
    it "creates message from hash with symbol keys" do
      hash = {
        id: "msg-1",
        topic: "user-events",
        payload: {user_id: 123},
        timestamp: "2026-04-09T12:00:00Z",
        attributes: {priority: "high"}
      }

      message = described_class.from_h(hash)

      expect(message.id).to eq("msg-1")
      expect(message.topic).to eq("user-events")
      expect(message.payload).to eq(user_id: 123)
      expect(message.attributes).to eq(priority: "high")
    end

    it "creates message from hash with string keys" do
      hash = {
        "id" => "msg-1",
        "topic" => "user-events",
        "payload" => {"user_id" => 123},
        "timestamp" => "2026-04-09T12:00:00Z"
      }

      message = described_class.from_h(hash)

      expect(message.id).to eq("msg-1")
      expect(message.topic).to eq("user-events")
    end

    it "parses timestamp from ISO8601 string" do
      hash = {
        topic: "test",
        payload: {},
        timestamp: "2026-04-09T12:00:00Z"
      }

      message = described_class.from_h(hash)

      expect(message.timestamp).to eq(Time.parse("2026-04-09 12:00:00 UTC"))
    end

    it "handles missing attributes" do
      hash = {
        topic: "test",
        payload: {}
      }

      message = described_class.from_h(hash)

      expect(message.attributes).to eq({})
    end
  end

  describe ".from_json" do
    it "creates message from JSON string" do
      json = '{"id":"msg-1","topic":"user-events","payload":{"user_id":123},"timestamp":"2026-04-09T12:00:00Z","attributes":{}}'

      message = described_class.from_json(json)

      expect(message.id).to eq("msg-1")
      expect(message.topic).to eq("user-events")
      expect(message.payload).to eq(user_id: 123)
    end
  end

  describe "#==" do
    it "returns true for messages with same id, topic, and payload" do
      msg1 = described_class.new(topic: "test", payload: {user_id: 123}, id: "msg-1")
      msg2 = described_class.new(topic: "test", payload: {user_id: 123}, id: "msg-1")

      expect(msg1).to eq(msg2)
    end

    it "returns false for messages with different id" do
      msg1 = described_class.new(topic: "test", payload: {}, id: "msg-1")
      msg2 = described_class.new(topic: "test", payload: {}, id: "msg-2")

      expect(msg1).not_to eq(msg2)
    end

    it "returns false for messages with different topic" do
      msg1 = described_class.new(topic: "topic1", payload: {}, id: "msg-1")
      msg2 = described_class.new(topic: "topic2", payload: {}, id: "msg-1")

      expect(msg1).not_to eq(msg2)
    end

    it "returns false for messages with different payload" do
      msg1 = described_class.new(topic: "test", payload: {a: 1}, id: "msg-1")
      msg2 = described_class.new(topic: "test", payload: {a: 2}, id: "msg-1")

      expect(msg1).not_to eq(msg2)
    end

    it "returns false when comparing with non-Message object" do
      message = described_class.new(topic: "test", payload: {})

      expect(message).not_to eq("not a message")
      expect(message).not_to eq(nil)
    end
  end

  describe "#hash" do
    it "returns same hash for equal messages" do
      msg1 = described_class.new(topic: "test", payload: {user_id: 123}, id: "msg-1")
      msg2 = described_class.new(topic: "test", payload: {user_id: 123}, id: "msg-1")

      expect(msg1.hash).to eq(msg2.hash)
    end

    it "allows messages to be used as hash keys" do
      msg1 = described_class.new(topic: "test", payload: {}, id: "msg-1")
      msg2 = described_class.new(topic: "test", payload: {}, id: "msg-1")

      hash = {msg1 => "value"}

      expect(hash[msg2]).to eq("value")
    end
  end
end

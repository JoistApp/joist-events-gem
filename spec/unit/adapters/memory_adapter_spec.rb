# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Adapters::MemoryAdapter do
  let(:adapter) { described_class.new }

  before do
    Joist::Events.configure do |config|
      config.register_adapter(:memory)
      config.default_adapter = :memory
    end
  end

  describe "#publish" do
    it "stores message in memory" do
      adapter.publish("user-events", '{"user_id": 123}')

      expect(adapter.messages["user-events"]).to eq(['{"user_id": 123}'])
    end

    it "stores multiple messages" do
      adapter.publish("user-events", "msg1")
      adapter.publish("user-events", "msg2")
      adapter.publish("other-events", "msg3")

      expect(adapter.messages["user-events"]).to eq(["msg1", "msg2"])
      expect(adapter.messages["other-events"]).to eq(["msg3"])
    end

    it "returns message ID by default (wait_for_ack: true)" do
      result = adapter.publish("test", "message")

      expect(result).to be_a(String)
      expect(result).to match(/^memory-test-\d+-\d+$/)
    end

    it "returns true with wait_for_ack: false" do
      result = adapter.publish("test", "message", wait_for_ack: false)

      expect(result).to be true
    end

    it "immediately delivers to active subscribers" do
      received = []

      # Subscribe before publishing
      Thread.new do
        adapter.subscribe("user-events", "test-sub") do |msg|
          received << msg
        end
      end

      sleep 0.01 # Give subscriber time to register

      adapter.publish("user-events", "msg1")
      adapter.publish("user-events", "msg2")

      sleep 0.01 # Give time for delivery

      expect(received).to eq(["msg1", "msg2"])
    end

    it "handles subscriber errors gracefully" do
      adapter.subscribe("user-events", "failing-sub") do |msg|
        raise StandardError, "Processing failed"
      end

      # Should not raise, just log error
      expect {
        adapter.publish("user-events", "msg1")
      }.not_to raise_error
    end
  end

  describe "#subscribe" do
    it "raises error without block" do
      expect {
        adapter.subscribe("test", "sub1")
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "registers subscriber" do
      adapter.subscribe("test", "sub1") { |msg| }

      expect(adapter.subscriber_count("test")).to eq(1)
    end

    it "receives messages published to topic" do
      received = []

      Thread.new do
        adapter.subscribe("user-events", "test-sub") do |msg|
          received << msg
        end
      end

      sleep 0.01

      adapter.publish("user-events", "message1")
      sleep 0.01

      expect(received).to include("message1")
    end

    it "multiple subscribers receive same message" do
      received1 = []
      received2 = []

      Thread.new do
        adapter.subscribe("test", "sub1") { |msg| received1 << msg }
      end

      Thread.new do
        adapter.subscribe("test", "sub2") { |msg| received2 << msg }
      end

      sleep 0.01

      adapter.publish("test", "msg1")
      sleep 0.01

      expect(received1).to eq(["msg1"])
      expect(received2).to eq(["msg1"])
      expect(adapter.subscriber_count("test")).to eq(2)
    end

    it "only receives messages for subscribed topic" do
      received = []

      Thread.new do
        adapter.subscribe("topic-a", "sub1") { |msg| received << msg }
      end

      sleep 0.01

      adapter.publish("topic-b", "wrong-topic")
      adapter.publish("topic-a", "correct-topic")
      sleep 0.01

      expect(received).to eq(["correct-topic"])
    end
  end

  describe "#stop" do
    it "stops the adapter" do
      adapter.start
      expect(adapter).to be_running

      adapter.stop

      expect(adapter).not_to be_running
    end
  end

  describe "#messages_for" do
    it "returns messages for specific topic" do
      adapter.publish("topic1", "msg1")
      adapter.publish("topic2", "msg2")
      adapter.publish("topic1", "msg3")

      expect(adapter.messages_for("topic1")).to eq(["msg1", "msg3"])
    end

    it "returns empty array for unknown topic" do
      expect(adapter.messages_for("unknown")).to eq([])
    end

    it "returns copy of messages" do
      adapter.publish("test", "msg1")

      messages = adapter.messages_for("test")
      messages << "msg2"

      expect(adapter.messages_for("test")).to eq(["msg1"])
    end
  end

  describe "#subscriber_count" do
    it "returns 0 for no subscribers" do
      expect(adapter.subscriber_count("test")).to eq(0)
    end

    it "returns count of subscribers for topic" do
      adapter.subscribe("test", "sub1") { |msg| }
      adapter.subscribe("test", "sub2") { |msg| }
      adapter.subscribe("other", "sub3") { |msg| }

      expect(adapter.subscriber_count("test")).to eq(2)
      expect(adapter.subscriber_count("other")).to eq(1)
    end
  end

  describe "#clear_messages" do
    it "removes all messages" do
      adapter.publish("test", "msg1")
      adapter.publish("other", "msg2")

      adapter.clear_messages

      expect(adapter.messages).to be_empty
    end
  end

  describe "#clear_subscribers" do
    it "removes all subscribers" do
      adapter.subscribe("test", "sub1") { |msg| }
      adapter.subscribe("test", "sub2") { |msg| }

      adapter.clear_subscribers

      expect(adapter.subscriber_count("test")).to eq(0)
    end
  end

  describe "#reset" do
    it "clears messages and subscribers" do
      adapter.publish("test", "msg1")
      adapter.subscribe("test", "sub1") { |msg| }
      adapter.start

      adapter.reset

      expect(adapter.messages).to be_empty
      expect(adapter.subscriber_count("test")).to eq(0)
      expect(adapter).not_to be_running
    end
  end

  describe "running?" do
    it "returns false initially" do
      expect(adapter).not_to be_running
    end

    it "returns true after start" do
      adapter.start

      expect(adapter).to be_running
    end

    it "returns false after stop" do
      adapter.start
      adapter.stop

      expect(adapter).not_to be_running
    end
  end
end

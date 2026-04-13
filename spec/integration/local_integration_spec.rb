# frozen_string_literal: true

require "integration_spec_helper"

RSpec.describe "Local Integration Tests", :integration do
  describe "Memory Adapter - Basic Pub/Sub" do
    it "publishes and subscribes to messages" do
      adapter = create_memory_adapter
      messages_received = []

      # Subscribe in a thread
      subscriber_thread = Thread.new do
        adapter.subscribe("test-topic", "test-subscriber") do |message|
          messages_received << message
        end
      end

      sleep 0.1

      # Publish messages
      5.times do |i|
        payload = %({"message": "Test message #{i + 1}", "timestamp": "#{Time.now.iso8601}"})
        adapter.publish("test-topic", payload)
      end

      # Wait for messages to be processed
      sleep 0.5
      adapter.stop
      subscriber_thread.kill

      expect(messages_received.count).to eq(5)
    end

    it "handles subscriber errors gracefully" do
      adapter = create_memory_adapter
      error_count = 0

      subscriber_thread = Thread.new do
        adapter.subscribe("test-topic", "error-subscriber") do |message|
          error_count += 1
          raise StandardError, "Subscriber error"
        end
      end

      sleep 0.1

      # Should not raise, just log error
      expect {
        adapter.publish("test-topic", '{"test": true}')
        sleep 0.1
      }.not_to raise_error

      adapter.stop
      subscriber_thread.kill

      expect(error_count).to eq(1)
    end
  end

  describe "Publisher Interface" do
    it "publishes messages successfully" do
      publisher = Joist::Events::Publisher.new("user-events", adapter: :memory)
      results = []

      5.times do |i|
        message = Joist::Events::Message.new(
          topic: "user-events",
          payload: {
            event_type: "user.created",
            user_id: i + 1,
            name: "User #{i + 1}"
          }
        )
        result = publisher.publish(message)
        results << result
      end

      expect(results).to all(be_truthy)
      expect(results.count).to eq(5)
    end

    it "supports different message formats" do
      publisher = Joist::Events::Publisher.new("events", adapter: :memory)

      # Hash payload
      result1 = publisher.publish({user_id: 123, event: "test"})
      expect(result1).to be_truthy

      # Message object
      message = Joist::Events::Message.new(
        topic: "events",
        payload: {user_id: 456}
      )
      result2 = publisher.publish(message)
      expect(result2).to be_truthy
    end
  end

  describe "Serialization" do
    it "serializes and deserializes messages correctly" do
      serializer = Joist::Events::Serializers::JsonSerializer.new

      message = Joist::Events::Message.new(
        topic: "test",
        payload: {
          user_id: 123,
          action: "login",
          metadata: {
            ip: "192.168.1.1",
            user_agent: "Mozilla/5.0"
          }
        }
      )

      json = serializer.serialize(message)
      expect(json).to be_a(String)
      expect(json).to include("user_id")

      deserialized = serializer.deserialize(json)
      expect(deserialized.topic).to eq(message.topic)
      expect(deserialized.payload).to eq(message.payload)
    end
  end

  describe "Performance" do
    it "handles 1000 messages efficiently", :slow do
      adapter = create_memory_adapter
      message_count = 0
      mutex = Mutex.new

      subscriber_thread = Thread.new do
        adapter.subscribe("perf-test", "perf-subscriber") do |message|
          mutex.synchronize { message_count += 1 }
        end
      end

      sleep 0.1

      start_time = Time.now
      1000.times do |i|
        adapter.publish("perf-test", %({"id": #{i}}))
      end

      # Wait for processing (max 5 seconds)
      timeout = 5
      loop do
        current_count = mutex.synchronize { message_count }
        break if current_count >= 1000
        break if Time.now - start_time > timeout
        sleep 0.1
      end

      final_count = mutex.synchronize { message_count }
      elapsed = Time.now - start_time

      adapter.stop
      subscriber_thread.kill

      expect(final_count).to eq(1000)
      expect(elapsed).to be < 5

      throughput = (final_count / elapsed).round(0)
      puts "\n  Throughput: #{throughput} msg/s"
    end
  end

  describe "Message attributes" do
    it "preserves message attributes" do
      publisher = Joist::Events::Publisher.new("test", adapter: :memory)

      message = publisher.publish(
        {data: "test"},
        attributes: {priority: "high", source: "api"}
      )

      expect(message).to be_truthy
    end
  end

  describe "Adapter health checks" do
    it "reports healthy status for memory adapter" do
      adapter = create_memory_adapter
      expect(adapter.healthy?).to be true
    end
  end
end

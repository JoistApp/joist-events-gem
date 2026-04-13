# frozen_string_literal: true

require "integration_spec_helper"

RSpec.describe "Publisher Acknowledgment", :integration do
  let(:publisher) { Joist::Events::Publisher.new("user-events") }
  let(:message) do
    Joist::Events::Message.new(
      topic: "user-events",
      payload: {user_id: 123, event: "user.created"}
    )
  end

  describe "wait_for_ack: true (default)" do
    it "returns message ID string" do
      result = publisher.publish(message)

      expect(result).to be_a(String)
      expect(result).to match(/^memory-user-events-\d+-\d+$/)
    end

    it "successfully publishes the message" do
      adapter = Joist::Events::Adapters::MemoryAdapter.new({})
      result = adapter.publish("test", '{"data": "value"}', wait_for_ack: true)

      expect(result).to be_a(String)
      expect(adapter.messages_for("test")).to include('{"data": "value"}')
    end
  end

  describe "wait_for_ack: false" do
    it "returns boolean true" do
      result = publisher.publish(message, wait_for_ack: false)

      expect(result).to eq(true)
      expect(result).to be_a(TrueClass)
    end

    it "successfully publishes the message" do
      adapter = Joist::Events::Adapters::MemoryAdapter.new({})
      result = adapter.publish("test", '{"data": "value"}', wait_for_ack: false)

      expect(result).to eq(true)
      expect(adapter.messages_for("test")).to include('{"data": "value"}')
    end
  end

  describe "adapter respects wait_for_ack option" do
    let(:adapter) { Joist::Events::Adapters::MemoryAdapter.new({}) }

    it "returns message ID with wait_for_ack: true" do
      result = adapter.publish("test", '{"message": "with ack"}', wait_for_ack: true)

      expect(result).to be_a(String)
      expect(result).to match(/^memory-test-\d+-\d+$/)
    end

    it "returns boolean with wait_for_ack: false" do
      result = adapter.publish("test", '{"message": "without ack"}', wait_for_ack: false)

      expect(result).to eq(true)
    end

    it "publishes messages regardless of ack mode" do
      adapter.publish("test", '{"message": "1"}', wait_for_ack: true)
      adapter.publish("test", '{"message": "2"}', wait_for_ack: false)

      expect(adapter.messages_for("test").count).to eq(2)
    end
  end

  describe "performance comparison" do
    it "publishes messages with both ack modes" do
      adapter_ack = Joist::Events::Adapters::MemoryAdapter.new({})
      adapter_no_ack = Joist::Events::Adapters::MemoryAdapter.new({})

      # Publish with ack
      start_time = Time.now
      100.times { |i| adapter_ack.publish("perf", %({"id": #{i}}), wait_for_ack: true) }
      duration_ack = Time.now - start_time

      # Publish without ack
      start_time = Time.now
      100.times { |i| adapter_no_ack.publish("perf", %({"id": #{i}}), wait_for_ack: false) }
      duration_no_ack = Time.now - start_time

      # Both should successfully publish
      expect(adapter_ack.messages_for("perf").count).to eq(100)
      expect(adapter_no_ack.messages_for("perf").count).to eq(100)

      # Log performance (informational only)
      puts "\n  Performance: ack=#{duration_ack.round(4)}s, no_ack=#{duration_no_ack.round(4)}s"
    end
  end

  describe "default behavior" do
    it "uses wait_for_ack: true by default" do
      # When no option is passed, it should return message ID (not boolean)
      result = publisher.publish(message)

      expect(result).not_to eq(true)
      expect(result).to be_a(String)
    end
  end
end

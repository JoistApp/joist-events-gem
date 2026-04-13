# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Middleware::Metrics do
  let(:backend) { Joist::Events::Middleware::MemoryMetricsBackend.new }
  let(:middleware) { described_class.new(backend: backend) }
  let(:message) { Joist::Events::Message.new(topic: "user-events", payload: {user_id: 123}) }

  describe ".new" do
    it "creates middleware with backend" do
      middleware = described_class.new(backend: backend)

      expect(middleware.backend).to eq(backend)
    end

    it "uses default namespace" do
      middleware = described_class.new(backend: backend)

      expect(middleware.namespace).to eq("joist.events")
    end

    it "accepts custom namespace" do
      middleware = described_class.new(backend: backend, namespace: "custom.metrics")

      expect(middleware.namespace).to eq("custom.metrics")
    end

    it "raises error if backend doesn't implement required methods" do
      invalid_backend = double("backend")

      expect {
        described_class.new(backend: invalid_backend)
      }.to raise_error(ArgumentError, /must implement #increment and #timing/)
    end
  end

  describe "#call" do
    it "records success metrics" do
      middleware.call(message) { :success }

      expect(backend.counter_value("joist.events.processed", topic: "user-events", message_id: message.id)).to eq(1)
      expect(backend.counter_value("joist.events.success", topic: "user-events", message_id: message.id)).to eq(1)
    end

    it "records timing metrics" do
      middleware.call(message) do
        sleep 0.01
        :success
      end

      timing = backend.timings.find { |t| t[:name] == "joist.events.duration" }

      expect(timing).not_to be_nil
      expect(timing[:duration]).to be > 0
      expect(timing[:tags][:topic]).to eq("user-events")
    end

    it "records failure metrics on error" do
      expect {
        middleware.call(message) { raise StandardError, "Processing failed" }
      }.to raise_error(StandardError, "Processing failed")

      expect(backend.counter_value("joist.events.processed", topic: "user-events", message_id: message.id)).to eq(1)
      expect(backend.counter_value("joist.events.failure", topic: "user-events", message_id: message.id, error_class: "StandardError")).to eq(1)
    end

    it "includes error class in failure tags" do
      custom_error = Class.new(StandardError)

      expect {
        middleware.call(message) { raise custom_error, "Custom error" }
      }.to raise_error(custom_error)

      failure_count = backend.counter_value(
        "joist.events.failure",
        topic: "user-events",
        message_id: message.id,
        error_class: custom_error.name
      )

      expect(failure_count).to eq(1)
    end

    it "records timing even on failure" do
      expect {
        middleware.call(message) do
          sleep 0.01
          raise "Error"
        end
      }.to raise_error("Error")

      timing = backend.timings.find { |t| t[:name] == "joist.events.duration" }

      expect(timing).not_to be_nil
      expect(timing[:duration]).to be > 0
    end

    it "returns result from block" do
      result = middleware.call(message) { :expected_result }

      expect(result).to eq(:expected_result)
    end

    it "re-raises errors after recording metrics" do
      expect {
        middleware.call(message) { raise ArgumentError, "Invalid" }
      }.to raise_error(ArgumentError, "Invalid")
    end

    it "uses custom namespace" do
      middleware = described_class.new(backend: backend, namespace: "custom.app")

      middleware.call(message) { :success }

      expect(backend.counter_value("custom.app.processed", topic: "user-events", message_id: message.id)).to eq(1)
    end

    it "includes message topic in tags" do
      middleware.call(message) { :success }

      timing = backend.timings.first
      expect(timing[:tags][:topic]).to eq("user-events")
    end

    it "includes message id in tags" do
      middleware.call(message) { :success }

      timing = backend.timings.first
      expect(timing[:tags][:message_id]).to eq(message.id)
    end
  end
end

RSpec.describe Joist::Events::Middleware::MemoryMetricsBackend do
  let(:backend) { described_class.new }

  describe "#increment" do
    it "increments counter by 1" do
      backend.increment("test.counter")

      expect(backend.counter_value("test.counter")).to eq(1)
    end

    it "accumulates multiple increments" do
      backend.increment("test.counter")
      backend.increment("test.counter")
      backend.increment("test.counter")

      expect(backend.counter_value("test.counter")).to eq(3)
    end

    it "tracks counters with different tags separately" do
      backend.increment("test.counter", topic: "topic1")
      backend.increment("test.counter", topic: "topic2")
      backend.increment("test.counter", topic: "topic1")

      expect(backend.counter_value("test.counter", topic: "topic1")).to eq(2)
      expect(backend.counter_value("test.counter", topic: "topic2")).to eq(1)
    end

    it "returns 0 for untracked counter" do
      expect(backend.counter_value("unknown.counter")).to eq(0)
    end
  end

  describe "#timing" do
    it "records timing with name and duration" do
      backend.timing("test.duration", 123.45)

      timing = backend.timings.first
      expect(timing[:name]).to eq("test.duration")
      expect(timing[:duration]).to eq(123.45)
    end

    it "records timing with tags" do
      backend.timing("test.duration", 100.0, topic: "events")

      timing = backend.timings.first
      expect(timing[:tags][:topic]).to eq("events")
    end

    it "stores multiple timings" do
      backend.timing("test.duration", 100.0)
      backend.timing("test.duration", 200.0)
      backend.timing("other.duration", 50.0)

      expect(backend.timings.size).to eq(3)
    end
  end

  describe "#clear" do
    it "clears all counters and timings" do
      backend.increment("test.counter")
      backend.timing("test.duration", 100.0)

      backend.clear

      expect(backend.counter_value("test.counter")).to eq(0)
      expect(backend.timings).to be_empty
    end
  end
end

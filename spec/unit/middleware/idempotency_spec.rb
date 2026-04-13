# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Middleware::Idempotency do
  let(:storage) { Joist::Events::Middleware::MemoryIdempotencyStorage.new }
  let(:middleware) { described_class.new(storage: storage, ttl: 3600) }
  let(:message) { Joist::Events::Message.new(topic: "test", payload: {user_id: 123}) }

  before do
    Joist::Events.configure do |config|
      config.register_adapter(:gcp, project_id: "test")
      config.default_adapter = :gcp
    end
  end

  describe ".new" do
    it "creates middleware with storage and ttl" do
      middleware = described_class.new(storage: storage, ttl: 1800)

      expect(middleware.storage).to eq(storage)
      expect(middleware.ttl).to eq(1800)
    end

    it "defaults ttl to 3600 seconds" do
      middleware = described_class.new(storage: storage)

      expect(middleware.ttl).to eq(3600)
    end

    it "raises error if storage doesn't implement required methods" do
      invalid_storage = double("storage")

      expect {
        described_class.new(storage: invalid_storage)
      }.to raise_error(ArgumentError, /must implement #processed\? and #mark_processed/)
    end
  end

  describe "#call" do
    it "processes message first time" do
      block_called = false

      result = middleware.call(message) do
        block_called = true
        :success
      end

      expect(result).to eq(:success)
      expect(block_called).to be true
    end

    it "marks message as processed after successful execution" do
      middleware.call(message) { :success }

      expect(storage.processed?(message.id)).to be true
    end

    it "skips processing for duplicate messages" do
      # Process first time
      middleware.call(message) { :first }

      # Try processing again
      block_called = false
      result = middleware.call(message) do
        block_called = true
        :second
      end

      expect(result).to eq(:duplicate)
      expect(block_called).to be false
    end

    it "doesn't mark as processed if block raises error" do
      expect {
        middleware.call(message) { raise StandardError, "Processing failed" }
      }.to raise_error(StandardError, "Processing failed")

      expect(storage.processed?(message.id)).to be false
    end

    it "allows retry after failed processing" do
      # First attempt fails
      expect {
        middleware.call(message) { raise "Temporary error" }
      }.to raise_error("Temporary error")

      # Second attempt succeeds
      result = middleware.call(message) { :success }

      expect(result).to eq(:success)
    end

    it "logs duplicate messages" do
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)

      # Process first time
      middleware.call(message) { :first }

      # Expect log for duplicate
      expect(logger).to receive(:info).with(/Skipping duplicate message/)

      middleware.call(message) { :second }
    end

    it "uses configured ttl when marking processed" do
      middleware = described_class.new(storage: storage, ttl: 1800)

      expect(storage).to receive(:mark_processed).with(message.id, 1800)

      middleware.call(message) { :success }
    end
  end
end

RSpec.describe Joist::Events::Middleware::MemoryIdempotencyStorage do
  let(:storage) { described_class.new }
  let(:message_id) { "msg-123" }

  describe "#processed?" do
    it "returns false for new message" do
      expect(storage.processed?(message_id)).to be false
    end

    it "returns true for processed message within ttl" do
      storage.mark_processed(message_id, 3600)

      expect(storage.processed?(message_id)).to be true
    end

    it "returns false for expired message" do
      storage.mark_processed(message_id, -1) # Already expired

      expect(storage.processed?(message_id)).to be false
    end
  end

  describe "#mark_processed" do
    it "marks message as processed with ttl" do
      storage.mark_processed(message_id, 3600)

      expect(storage.processed?(message_id)).to be true
    end

    it "updates expiry for already processed message" do
      storage.mark_processed(message_id, -1) # Expired
      expect(storage.processed?(message_id)).to be false

      storage.mark_processed(message_id, 3600) # Update with new ttl
      expect(storage.processed?(message_id)).to be true
    end
  end

  describe "#clear" do
    it "removes all processed messages" do
      storage.mark_processed("msg-1", 3600)
      storage.mark_processed("msg-2", 3600)

      storage.clear

      expect(storage.processed?("msg-1")).to be false
      expect(storage.processed?("msg-2")).to be false
    end
  end
end

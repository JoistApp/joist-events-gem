# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Middleware::Retry do
  let(:middleware) { described_class.new }
  let(:message) { Joist::Events::Message.new(topic: "test", payload: {}) }

  before do
    Joist::Events.configure do |config|
      config.register_adapter(:gcp, project_id: "test")
      config.default_adapter = :gcp
    end
  end

  describe ".new" do
    it "creates middleware with default options" do
      middleware = described_class.new

      expect(middleware.max_attempts).to eq(3)
      expect(middleware.base_delay).to eq(1.0)
      expect(middleware.max_delay).to eq(60.0)
      expect(middleware.backoff_factor).to eq(2.0)
    end

    it "accepts custom options" do
      middleware = described_class.new(
        max_attempts: 5,
        base_delay: 0.5,
        max_delay: 30.0,
        backoff_factor: 3.0
      )

      expect(middleware.max_attempts).to eq(5)
      expect(middleware.base_delay).to eq(0.5)
      expect(middleware.max_delay).to eq(30.0)
      expect(middleware.backoff_factor).to eq(3.0)
    end

    it "raises error for invalid max_attempts" do
      expect {
        described_class.new(max_attempts: 0)
      }.to raise_error(ArgumentError, /max_attempts must be >= 1/)
    end

    it "raises error for invalid base_delay" do
      expect {
        described_class.new(base_delay: 0)
      }.to raise_error(ArgumentError, /base_delay must be > 0/)
    end

    it "raises error for invalid max_delay" do
      expect {
        described_class.new(max_delay: -1)
      }.to raise_error(ArgumentError, /max_delay must be > 0/)
    end

    it "raises error for invalid backoff_factor" do
      expect {
        described_class.new(backoff_factor: 0.5)
      }.to raise_error(ArgumentError, /backoff_factor must be >= 1/)
    end

    it "accepts on_retry callback" do
      callback = ->(error, attempt, message) {}
      middleware = described_class.new(on_retry: callback)

      expect(middleware.on_retry).to eq(callback)
    end
  end

  describe "#call" do
    it "executes block successfully on first attempt" do
      result = middleware.call(message) { :success }

      expect(result).to eq(:success)
    end

    it "retries on retriable error" do
      attempt_count = 0
      middleware = described_class.new(max_attempts: 3, base_delay: 0.01)

      result = middleware.call(message) do
        attempt_count += 1
        raise StandardError, "Temporary error" if attempt_count < 2
        :success
      end

      expect(result).to eq(:success)
      expect(attempt_count).to eq(2)
    end

    it "raises error after max attempts exhausted" do
      middleware = described_class.new(max_attempts: 3, base_delay: 0.01)
      attempt_count = 0

      expect {
        middleware.call(message) do
          attempt_count += 1
          raise StandardError, "Persistent error"
        end
      }.to raise_error(Joist::Events::MiddlewareError, /Retry exhausted after 3 attempts/)

      expect(attempt_count).to eq(3)
    end

    it "applies exponential backoff" do
      middleware = described_class.new(
        max_attempts: 3,
        base_delay: 0.1,
        backoff_factor: 2.0
      )
      attempt_count = 0
      delays = []

      expect {
        middleware.call(message) do
          if attempt_count > 0
            delays << Time.now
          end
          attempt_count += 1
          raise StandardError, "Error"
        end
      }.to raise_error(Joist::Events::MiddlewareError)

      # Verify increasing delays (approximately)
      if delays.size >= 2
        delay1 = delays[1] - delays[0]
        delay2 = delays[2] - delays[1] if delays[2]

        expect(delay2).to be > delay1 if delay2
      end
    end

    it "respects max_delay cap" do
      middleware = described_class.new(
        max_attempts: 5,
        base_delay: 10.0,
        max_delay: 0.05, # Very low max to test capping
        backoff_factor: 2.0
      )

      allow(middleware).to receive(:sleep) # Don't actually sleep

      expect {
        middleware.call(message) { raise "Error" }
      }.to raise_error(Joist::Events::MiddlewareError)

      # Verify sleep was called with capped delays
      expect(middleware).to have_received(:sleep).at_least(:once).with(be <= 0.05)
    end

    it "calls on_retry callback" do
      callback_calls = []
      callback = ->(error, attempt, msg) do
        callback_calls << {error: error, attempt: attempt, message: msg}
      end

      middleware = described_class.new(
        max_attempts: 3,
        base_delay: 0.01,
        on_retry: callback
      )
      attempt_count = 0

      expect {
        middleware.call(message) do
          attempt_count += 1
          raise StandardError, "Error #{attempt_count}"
        end
      }.to raise_error(Joist::Events::MiddlewareError)

      expect(callback_calls.size).to eq(2) # 2 retries before final failure
      expect(callback_calls[0][:attempt]).to eq(1)
      expect(callback_calls[0][:message]).to eq(message)
      expect(callback_calls[0][:error].message).to eq("Error 1")

      expect(callback_calls[1][:attempt]).to eq(2)
      expect(callback_calls[1][:error].message).to eq("Error 2")
    end

    it "logs retry attempts" do
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)

      middleware = described_class.new(max_attempts: 2, base_delay: 0.01)
      attempt_count = 0

      expect(logger).to receive(:warn).with(/Retrying message/)
      expect(logger).to receive(:error).with(/Retry exhausted/)

      expect {
        middleware.call(message) do
          attempt_count += 1
          raise StandardError, "Error"
        end
      }.to raise_error(Joist::Events::MiddlewareError)
    end

    it "logs exhausted retries" do
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)

      middleware = described_class.new(max_attempts: 2, base_delay: 0.01)

      expect(logger).to receive(:warn).once # First retry
      expect(logger).to receive(:error).with(/Retry exhausted/)

      expect {
        middleware.call(message) { raise StandardError, "Error" }
      }.to raise_error(Joist::Events::MiddlewareError)
    end

    it "only retries specified error classes" do
      custom_error = Class.new(StandardError)
      other_error = Class.new(StandardError)

      middleware = described_class.new(
        max_attempts: 3,
        base_delay: 0.01,
        retriable_errors: [custom_error]
      )

      # Should retry custom_error
      attempt_count = 0
      result = middleware.call(message) do
        attempt_count += 1
        raise custom_error, "Retriable" if attempt_count < 2
        :success
      end

      expect(result).to eq(:success)
      expect(attempt_count).to eq(2)

      # Should not retry other_error
      expect {
        middleware.call(message) { raise other_error, "Not retriable" }
      }.to raise_error(other_error, "Not retriable")
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Middleware::Base do
  let(:message) { Joist::Events::Message.new(topic: "test", payload: {}) }
  let(:middleware) { described_class.new }

  describe "#call" do
    it "raises NotImplementedError if not overridden" do
      expect {
        middleware.call(message) { :result }
      }.to raise_error(NotImplementedError, /must implement #call/)
    end
  end

  describe "custom middleware" do
    let(:custom_middleware) do
      Class.new(described_class) do
        def call(message, &block)
          message.payload[:middleware_called] = true
          result = block.call
          "wrapped: #{result}"
        end
      end.new
    end

    it "can wrap block execution" do
      result = custom_middleware.call(message) { "original" }

      expect(result).to eq("wrapped: original")
      expect(message.payload[:middleware_called]).to be true
    end

    it "receives message and block" do
      block_called = false

      custom_middleware.call(message) do
        block_called = true
        "done"
      end

      expect(block_called).to be true
    end
  end
end

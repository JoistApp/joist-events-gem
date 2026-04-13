# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Middleware::Chain do
  let(:message) { Joist::Events::Message.new(topic: "test", payload: {}) }
  let(:chain) { described_class.new }

  describe "#add" do
    it "adds middleware to the chain" do
      middleware = double("middleware", call: nil)

      chain.add(middleware)

      expect(chain.size).to eq(1)
    end

    it "returns self for chaining" do
      middleware = double("middleware", call: nil)

      result = chain.add(middleware)

      expect(result).to eq(chain)
    end

    it "raises error if middleware doesn't respond to call" do
      invalid_middleware = double("invalid")

      expect {
        chain.add(invalid_middleware)
      }.to raise_error(ArgumentError, /must respond to #call/)
    end

    it "can add multiple middlewares" do
      middleware1 = double("middleware1", call: nil)
      middleware2 = double("middleware2", call: nil)

      chain.add(middleware1).add(middleware2)

      expect(chain.size).to eq(2)
    end
  end

  describe "#call" do
    it "executes final block when chain is empty" do
      result = chain.call(message) { :final_result }

      expect(result).to eq(:final_result)
    end

    it "executes middlewares in order" do
      execution_order = []

      middleware1 = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          execution_order << :middleware1_before
          result = block.call
          execution_order << :middleware1_after
          result
        end
      end.new

      middleware2 = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          execution_order << :middleware2_before
          result = block.call
          execution_order << :middleware2_after
          result
        end
      end.new

      chain.add(middleware1).add(middleware2)

      chain.call(message) { execution_order << :final_block }

      expect(execution_order).to eq([
        :middleware1_before,
        :middleware2_before,
        :final_block,
        :middleware2_after,
        :middleware1_after
      ])
    end

    it "passes message to each middleware" do
      received_messages = []

      middleware1 = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          received_messages << msg
          block.call
        end
      end.new

      middleware2 = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          received_messages << msg
          block.call
        end
      end.new

      chain.add(middleware1).add(middleware2)
      chain.call(message) { :done }

      expect(received_messages).to all(eq(message))
      expect(received_messages.size).to eq(2)
    end

    it "returns result from final block" do
      middleware = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          block.call
        end
      end.new

      chain.add(middleware)

      result = chain.call(message) { :final_result }

      expect(result).to eq(:final_result)
    end

    it "allows middleware to modify result" do
      middleware = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          result = block.call
          "wrapped: #{result}"
        end
      end.new

      chain.add(middleware)

      result = chain.call(message) { "original" }

      expect(result).to eq("wrapped: original")
    end

    it "stops execution if middleware doesn't call block" do
      block_executed = false

      middleware = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          # Don't call block
          :short_circuit
        end
      end.new

      chain.add(middleware)

      result = chain.call(message) do
        block_executed = true
        :never_reached
      end

      expect(result).to eq(:short_circuit)
      expect(block_executed).to be false
    end

    it "propagates exceptions through middleware" do
      middleware = Class.new(Joist::Events::Middleware::Base) do
        define_method(:call) do |msg, &block|
          block.call
        rescue => e
          raise "Wrapped: #{e.message}"
        end
      end.new

      chain.add(middleware)

      expect {
        chain.call(message) { raise "Original error" }
      }.to raise_error("Wrapped: Original error")
    end
  end

  describe "#empty?" do
    it "returns true when no middlewares added" do
      expect(chain.empty?).to be true
    end

    it "returns false when middlewares present" do
      middleware = double("middleware", call: nil)
      chain.add(middleware)

      expect(chain.empty?).to be false
    end
  end

  describe "#size" do
    it "returns 0 for empty chain" do
      expect(chain.size).to eq(0)
    end

    it "returns count of middlewares" do
      middleware1 = double("middleware1", call: nil)
      middleware2 = double("middleware2", call: nil)

      chain.add(middleware1).add(middleware2)

      expect(chain.size).to eq(2)
    end
  end

  describe "#clear" do
    it "removes all middlewares" do
      middleware = double("middleware", call: nil)
      chain.add(middleware)

      chain.clear

      expect(chain.empty?).to be true
      expect(chain.size).to eq(0)
    end

    it "returns self for chaining" do
      result = chain.clear

      expect(result).to eq(chain)
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Subscriber do
  # Test subscriber class
  class TestSubscriber < Joist::Events::Subscriber
    topic "user-events"
    subscriber_name "test-service"

    attr_reader :consumed_messages

    def initialize(options = {})
      @consumed_messages = []
      super
    end

    def consume!(message)
      @consumed_messages << message
    end
  end

  before do
    Joist::Events.configure do |config|
      config.register_adapter(:memory)
      config.default_adapter = :memory
    end
  end

  describe "class methods" do
    it "allows setting topic" do
      expect(TestSubscriber.topic_name).to eq("user-events")
    end

    it "allows setting subscriber_name" do
      expect(TestSubscriber.subscriber_name).to eq("test-service")
    end
  end

  describe ".new" do
    context "when adapter is configured" do
      it "creates subscriber with adapter" do
        subscriber = TestSubscriber.new

        expect(subscriber.topic).to eq("user-events")
        expect(subscriber.name).to eq("test-service")
      end
    end

    xit "creates subscriber with default options" do
      subscriber = TestSubscriber.new

      expect(subscriber.topic).to eq("user-events")
      expect(subscriber.name).to eq("test-service")
      expect(subscriber.options).to eq({})
    end

    xit "accepts adapter options" do
      subscriber = TestSubscriber.new(
        prefetch: 10,
        manual_ack: true
      )

      expect(subscriber.options).to include(
        prefetch: 10,
        manual_ack: true
      )
    end

    xit "uses default adapter if not specified" do
      subscriber = TestSubscriber.new

      expect(subscriber.adapter).to be_a(Joist::Events::Adapters::GcpAdapter)
    end

    xit "uses specified adapter" do
      Joist::Events.configuration.register_adapter(:amazon_mq, host: "localhost")

      subscriber = TestSubscriber.new(adapter: :amazon_mq)

      expect(subscriber.adapter).to be_a(Joist::Events::Adapters::AmazonMqAdapter)
    end

    it "raises error if topic not set" do
      klass = Class.new(Joist::Events::Subscriber) do
        subscriber_name "test"
      end

      expect {
        klass.new
      }.to raise_error(ArgumentError, "topic must be set")
    end

    it "raises error if subscriber_name not set" do
      klass = Class.new(Joist::Events::Subscriber) do
        topic "test-topic"
      end

      expect {
        klass.new
      }.to raise_error(ArgumentError, "subscriber_name must be set")
    end
  end

  describe "#subscribe!" do
    xit "starts the subscriber" do
      subscriber = TestSubscriber.new
      adapter = double("adapter")
      allow(subscriber).to receive(:adapter).and_return(adapter)

      expect(adapter).to receive(:subscribe).with("user-events", "test-service", {})

      Thread.new { subscriber.subscribe! }
      sleep 0.1 # Give it time to start

      subscriber.stop!
    end

    xit "processes messages through consume!" do
      subscriber = TestSubscriber.new
      adapter = double("adapter")
      allow(subscriber).to receive(:adapter).and_return(adapter)

      message = Joist::Events::Message.new(
        topic: "user-events",
        payload: {user_id: 123}
      )

      allow(adapter).to receive(:subscribe) do |topic, name, options, &block|
        block.call(message)
      end

      Thread.new { subscriber.subscribe! }
      sleep 0.1

      expect(subscriber.consumed_messages).to include(message)

      subscriber.stop!
    end

    xit "sets running flag" do
      subscriber = TestSubscriber.new

      expect(subscriber.running?).to be false

      Thread.new { subscriber.subscribe! }
      sleep 0.1

      expect(subscriber.running?).to be true

      subscriber.stop!
    end

    xit "logs start" do
      subscriber = TestSubscriber.new
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)

      expect(logger).to receive(:info).with(/Starting subscriber/)

      Thread.new { subscriber.subscribe! }
      sleep 0.1

      subscriber.stop!
    end

    xit "raises SubscribeError on failure" do
      subscriber = TestSubscriber.new
      adapter = double("adapter")
      allow(subscriber).to receive(:adapter).and_return(adapter)
      allow(adapter).to receive(:subscribe).and_raise(StandardError, "Connection failed")

      expect {
        subscriber.subscribe!
      }.to raise_error(Joist::Events::SubscribeError, /Failed to subscribe: Connection failed/)
    end
  end

  describe "#stop!" do
    xit "stops the subscriber" do
      subscriber = TestSubscriber.new
      adapter = double("adapter", stop: true)
      allow(subscriber).to receive(:adapter).and_return(adapter)
      allow(adapter).to receive(:subscribe) { sleep 10 } # Long-running

      Thread.new { subscriber.subscribe! }
      sleep 0.1

      expect(subscriber.running?).to be true

      subscriber.stop!

      expect(subscriber.running?).to be false
    end

    xit "calls adapter.stop if available" do
      subscriber = TestSubscriber.new
      adapter = double("adapter")
      allow(subscriber).to receive(:adapter).and_return(adapter)

      expect(adapter).to receive(:stop)

      subscriber.stop!
    end

    xit "logs stop" do
      subscriber = TestSubscriber.new
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)

      expect(logger).to receive(:info).with(/Stopped subscriber/)

      subscriber.stop!
    end
  end

  describe "#consume!" do
    it "raises NotImplementedError if not overridden" do
      klass = Class.new(Joist::Events::Subscriber) do
        topic "test"
        subscriber_name "test"
      end

      subscriber = klass.allocate # Skip initialize

      message = Joist::Events::Message.new(topic: "test", payload: {})

      expect {
        subscriber.consume!(message)
      }.to raise_error(NotImplementedError, /must implement #consume!/)
    end
  end

  describe "#process_message (private)" do
    xit "parses hash to Message" do
      subscriber = TestSubscriber.new
      hash = {topic: "user-events", payload: {user_id: 123}}

      subscriber.send(:process_message, hash)

      expect(subscriber.consumed_messages.first).to be_a(Joist::Events::Message)
      expect(subscriber.consumed_messages.first.payload).to eq(user_id: 123)
    end

    xit "parses JSON string to Message" do
      subscriber = TestSubscriber.new
      json = '{"topic":"user-events","payload":{"user_id":123}}'

      subscriber.send(:process_message, json)

      expect(subscriber.consumed_messages.first).to be_a(Joist::Events::Message)
      expect(subscriber.consumed_messages.first.payload).to eq(user_id: 123)
    end

    xit "accepts Message object directly" do
      subscriber = TestSubscriber.new
      message = Joist::Events::Message.new(
        topic: "user-events",
        payload: {user_id: 123}
      )

      subscriber.send(:process_message, message)

      expect(subscriber.consumed_messages.first).to eq(message)
    end

    xit "raises SubscribeError for unknown format" do
      subscriber = TestSubscriber.new

      expect {
        subscriber.send(:process_message, 12345)
      }.to raise_error(Joist::Events::SubscribeError, /Unknown message format: Integer/)
    end

    xit "logs consumed message" do
      subscriber = TestSubscriber.new
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)
      message = Joist::Events::Message.new(topic: "test", payload: {})

      expect(logger).to receive(:debug).with(/Consumed message/)

      subscriber.send(:process_message, message)
    end

    xit "logs errors" do
      klass = Class.new(Joist::Events::Subscriber) do
        topic "test"
        subscriber_name "test"

        def consume!(message)
          raise StandardError, "Processing failed"
        end
      end

      subscriber = klass.new
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)
      message = Joist::Events::Message.new(topic: "test", payload: {})

      expect(logger).to receive(:error).with(/Failed to process message/)

      expect {
        subscriber.send(:process_message, message)
      }.to raise_error(StandardError, "Processing failed")
    end
  end
end

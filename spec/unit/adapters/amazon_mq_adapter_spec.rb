# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Adapters::AmazonMqAdapter do
  let(:adapter) do
    described_class.new(
      host: "localhost",
      username: "admin",
      password: "password"
    )
  end

  describe ".new" do
    it "creates adapter with required options" do
      adapter = described_class.new(
        host: "broker.example.com",
        username: "user",
        password: "pass"
      )

      expect(adapter.options[:host]).to eq("broker.example.com")
      expect(adapter.options[:username]).to eq("user")
    end

    it "raises error without host" do
      expect {
        described_class.new(username: "user", password: "pass")
      }.to raise_error(ArgumentError, /host is required/)
    end

    it "raises error without username" do
      expect {
        described_class.new(host: "localhost", password: "pass")
      }.to raise_error(ArgumentError, /username is required/)
    end

    it "raises error without password" do
      expect {
        described_class.new(host: "localhost", username: "user")
      }.to raise_error(ArgumentError, /password is required/)
    end

    it "defaults port to 5672" do
      adapter = described_class.new(
        host: "localhost",
        username: "user",
        password: "pass"
      )

      # Port is not stored in options, it's an instance variable
      expect(adapter.instance_variable_get(:@port)).to eq(5672)
    end

    it "uses port 5671 for TLS" do
      adapter = described_class.new(
        host: "localhost",
        username: "user",
        password: "pass",
        tls: true
      )

      expect(adapter.instance_variable_get(:@port)).to eq(5671)
    end

    it "accepts custom port" do
      adapter = described_class.new(
        host: "localhost",
        port: 5555,
        username: "user",
        password: "pass"
      )

      expect(adapter.instance_variable_get(:@port)).to eq(5555)
    end

    it "accepts vhost option" do
      adapter = described_class.new(
        host: "localhost",
        username: "user",
        password: "pass",
        vhost: "/production"
      )

      expect(adapter.instance_variable_get(:@vhost)).to eq("/production")
    end

    it "defaults vhost to /" do
      expect(adapter.instance_variable_get(:@vhost)).to eq("/")
    end
  end

  describe "#publish" do
    let(:connection_mock) { double("connection", open?: true, start: nil, create_channel: channel_mock) }
    let(:exchange_mock) { double("exchange") }

    it "publishes message to exchange and returns message ID" do
      channel_mock = double("channel",
        open?: true,
        using_publisher_confirmations?: false,
        confirm_select: nil,
        wait_for_confirms: true,
        exchange: exchange_mock)

      adapter.instance_variable_set(:@channel, channel_mock)
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).with("user-events").and_return(exchange_mock)

      expect(exchange_mock).to receive(:publish).with(
        '{"user_id": 123}',
        routing_key: "user-events",
        persistent: true,
        content_type: "application/json"
      )

      result = adapter.publish("user-events", '{"user_id": 123}')

      expect(result).to be_a(String)
      expect(result).to match(/^user-events-\d+-\d+$/)
    end

    it "publishes with wait_for_ack: false" do
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).with("user-events").and_return(exchange_mock)

      expect(exchange_mock).to receive(:publish).with(
        '{"user_id": 123}',
        routing_key: "user-events",
        persistent: true,
        content_type: "application/json"
      )

      result = adapter.publish("user-events", '{"user_id": 123}', wait_for_ack: false)

      expect(result).to be true
    end

    it "ensures connection before publishing" do
      expect(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(exchange_mock).to receive(:publish)

      adapter.publish("test", "message", wait_for_ack: false)
    end

    it "wraps Bunny errors" do
      allow(adapter).to receive(:ensure_connected!).and_raise(Bunny::Exception, "Connection failed")

      expect {
        adapter.publish("test", "message")
      }.to raise_error(Joist::Events::AdapterError, /RabbitMQ publish error/)
    end
  end

  describe "#subscribe" do
    let(:connection_mock) { double("connection", open?: true, start: nil, create_channel: channel_mock) }
    let(:channel_mock) { double("channel", open?: true, exchange: exchange_mock, queue: queue_mock, prefetch: nil) }
    let(:exchange_mock) { double("exchange") }
    let(:queue_mock) { double("queue", bind: nil, subscribe: consumer_mock) }
    let(:consumer_mock) { double("consumer") }

    before do
      allow(Bunny).to receive(:new).and_return(connection_mock)
      adapter.instance_variable_set(:@connection, connection_mock)
      adapter.instance_variable_set(:@channel, channel_mock)
    end

    it "raises error without block" do
      expect {
        adapter.subscribe("test", "sub1")
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "creates durable queue" do
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)

      expect(channel_mock).to receive(:queue).with(
        "user-events.test-sub",
        durable: true,
        auto_delete: false
      ).and_return(queue_mock)

      adapter.subscribe("user-events", "test-sub") { |msg| }
    end

    it "binds queue to exchange with routing key" do
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).with("user-events").and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)

      expect(queue_mock).to receive(:bind).with(exchange_mock, routing_key: "user-events")

      adapter.subscribe("user-events", "test-sub") { |msg| }
    end

    it "sets prefetch count" do
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)

      expect(channel_mock).to receive(:prefetch).with(20)

      adapter.subscribe("test", "sub1", prefetch: 20) { |msg| }
    end

    it "defaults prefetch to 10" do
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)

      expect(channel_mock).to receive(:prefetch).with(10)

      adapter.subscribe("test", "sub1") { |msg| }
    end

    it "subscribes with auto-ack by default" do
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)

      expect(queue_mock).to receive(:subscribe).with(
        manual_ack: false,
        block: true
      ).and_return(consumer_mock)

      adapter.subscribe("test", "sub1") { |msg| }
    end

    it "supports manual acknowledgment" do
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)

      expect(queue_mock).to receive(:subscribe).with(
        manual_ack: true,
        block: true
      ).and_return(consumer_mock)

      adapter.subscribe("test", "sub1", manual_ack: true) { |msg| }
    end

    it "calls block with message payload" do
      received = []
      delivery_info = double("delivery_info", delivery_tag: 123)
      properties = double("properties")

      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)
      allow(queue_mock).to receive(:subscribe) do |**options, &block|
        block.call(delivery_info, properties, "test-message")
        consumer_mock
      end

      adapter.subscribe("test", "sub1") do |msg|
        received << msg
      end

      expect(received).to eq(["test-message"])
    end

    it "acknowledges message with manual ack" do
      delivery_info = double("delivery_info", delivery_tag: 123)
      properties = double("properties")

      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)
      allow(queue_mock).to receive(:subscribe) do |**options, &block|
        block.call(delivery_info, properties, "msg")
        consumer_mock
      end

      expect(channel_mock).to receive(:ack).with(123)

      adapter.subscribe("test", "sub1", manual_ack: true) { |msg| }
    end

    it "nacks and requeues message on error with manual ack" do
      delivery_info = double("delivery_info", delivery_tag: 123)
      properties = double("properties")
      logger = double("logger")

      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)
      allow(adapter).to receive(:ensure_connected!)
      allow(adapter).to receive(:ensure_exchange).and_return(exchange_mock)
      allow(channel_mock).to receive(:queue).and_return(queue_mock)
      allow(queue_mock).to receive(:subscribe) do |**options, &block|
        block.call(delivery_info, properties, "msg")
        consumer_mock
      end

      expect(logger).to receive(:error).with(/Error processing message/)
      expect(channel_mock).to receive(:nack).with(123, false, true)

      expect {
        adapter.subscribe("test", "sub1", manual_ack: true) { |msg| raise "Processing error" }
      }.to raise_error("Processing error")
    end

    it "wraps Bunny subscribe errors" do
      allow(adapter).to receive(:ensure_connected!).and_raise(Bunny::Exception, "Connection failed")

      expect {
        adapter.subscribe("test", "sub1") { |msg| }
      }.to raise_error(Joist::Events::AdapterError, /RabbitMQ subscribe error/)
    end
  end

  describe "#stop" do
    let(:consumer1) { double("consumer1", cancel: nil) }
    let(:consumer2) { double("consumer2", cancel: nil) }
    let(:channel_mock) { double("channel", close: nil) }
    let(:connection_mock) { double("connection", close: nil) }

    it "cancels all subscriptions" do
      adapter.instance_variable_set(:@subscriptions, [consumer1, consumer2])

      expect(consumer1).to receive(:cancel)
      expect(consumer2).to receive(:cancel)

      adapter.stop
    end

    it "closes channel and connection" do
      adapter.instance_variable_set(:@channel, channel_mock)
      adapter.instance_variable_set(:@connection, connection_mock)

      expect(channel_mock).to receive(:close)
      expect(connection_mock).to receive(:close)

      adapter.stop
    end

    it "logs errors but doesn't raise" do
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)
      adapter.instance_variable_set(:@connection, connection_mock)

      allow(connection_mock).to receive(:close).and_raise(Bunny::Exception, "Close failed")
      expect(logger).to receive(:error).with(/Error stopping RabbitMQ adapter/)

      expect { adapter.stop }.not_to raise_error
    end
  end

  describe "#healthy?" do
    let(:connection_mock) { double("connection") }
    let(:channel_mock) { double("channel") }

    it "returns true when connection and channel are open" do
      adapter.instance_variable_set(:@connection, connection_mock)
      adapter.instance_variable_set(:@channel, channel_mock)

      allow(connection_mock).to receive(:open?).and_return(true)
      allow(channel_mock).to receive(:open?).and_return(true)

      expect(adapter.healthy?).to be true
    end

    it "returns false when connection is closed" do
      adapter.instance_variable_set(:@connection, connection_mock)
      adapter.instance_variable_set(:@channel, channel_mock)

      allow(connection_mock).to receive(:open?).and_return(false)
      allow(channel_mock).to receive(:open?).and_return(true)

      expect(adapter.healthy?).to be false
    end

    it "returns false when channel is closed" do
      adapter.instance_variable_set(:@connection, connection_mock)
      adapter.instance_variable_set(:@channel, channel_mock)

      allow(connection_mock).to receive(:open?).and_return(true)
      allow(channel_mock).to receive(:open?).and_return(false)

      expect(adapter.healthy?).to be false
    end

    it "returns false when no connection" do
      expect(adapter.healthy?).to be false
    end

    it "returns false on error" do
      adapter.instance_variable_set(:@connection, connection_mock)

      allow(connection_mock).to receive(:open?).and_raise(StandardError)

      expect(adapter.healthy?).to be false
    end
  end
end

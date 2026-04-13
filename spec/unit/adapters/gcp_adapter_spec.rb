# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Adapters::GcpAdapter do
  let(:pubsub_mock) { double("pubsub", project_id: "test-project") }
  let(:adapter) do
    allow(Google::Cloud::PubSub).to receive(:new).and_return(pubsub_mock)
    described_class.new(project_id: "test-project")
  end

  describe ".new" do
    it "creates adapter with project_id" do
      allow(Google::Cloud::PubSub).to receive(:new).and_return(pubsub_mock)
      adapter = described_class.new(project_id: "my-project")

      expect(adapter.project_id).to eq("my-project")
    end

    it "raises error without project_id" do
      expect {
        described_class.new
      }.to raise_error(ArgumentError, /project_id is required/)
    end

    it "accepts credentials option" do
      allow(Google::Cloud::PubSub).to receive(:new).and_return(pubsub_mock)
      adapter = described_class.new(
        project_id: "test",
        credentials: "/path/to/creds.json"
      )

      expect(adapter.options[:credentials]).to eq("/path/to/creds.json")
    end

    it "accepts emulator_host option" do
      allow(Google::Cloud::PubSub).to receive(:new).and_return(pubsub_mock)
      adapter = described_class.new(
        project_id: "test",
        emulator_host: "localhost:8085"
      )

      expect(adapter.options[:emulator_host]).to eq("localhost:8085")
    end

    it "initializes pubsub client" do
      expect(adapter.pubsub).to eq(pubsub_mock)
    end
  end

  describe "#publish" do
    let(:topic_mock) { double("topic") }
    let(:pubsub_mock) { double("pubsub", topic: topic_mock) }

    before do
      allow(adapter).to receive(:pubsub).and_return(pubsub_mock)
    end

    it "publishes message to topic and returns message ID" do
      result_mock = double("result")
      allow(result_mock).to receive(:respond_to?).with(:message_id).and_return(true)
      allow(result_mock).to receive(:message_id).and_return("msg-12345")

      expect(pubsub_mock).to receive(:topic).with("user-events", skip_lookup: true).and_return(topic_mock)
      expect(topic_mock).to receive(:publish).with('{"user_id": 123}').and_return(result_mock)

      result = adapter.publish("user-events", '{"user_id": 123}')

      expect(result).to eq("msg-12345")
    end

    it "publishes message with wait_for_ack: false" do
      result_mock = double("result")

      expect(pubsub_mock).to receive(:topic).with("user-events", skip_lookup: true).and_return(topic_mock)
      expect(topic_mock).to receive(:publish).with('{"user_id": 123}').and_return(result_mock)

      result = adapter.publish("user-events", '{"user_id": 123}', wait_for_ack: false)

      expect(result).to be true
    end

    it "raises error if topic not found" do
      allow(pubsub_mock).to receive(:topic).and_return(nil)

      expect {
        adapter.publish("missing-topic", "message")
      }.to raise_error(Joist::Events::AdapterError, /Topic missing-topic not found/)
    end

    it "raises error if publish fails" do
      allow(pubsub_mock).to receive(:topic).and_return(topic_mock)
      allow(topic_mock).to receive(:publish).and_return(nil)

      expect {
        adapter.publish("test", "message")
      }.to raise_error(Joist::Events::AdapterError, /Failed to publish/)
    end

    it "wraps GCP errors" do
      allow(pubsub_mock).to receive(:topic).and_raise(Google::Cloud::Error, "Connection failed")

      expect {
        adapter.publish("test", "message")
      }.to raise_error(Joist::Events::AdapterError, /GCP Pub\/Sub error/)
    end
  end

  describe "#subscribe" do
    let(:topic_mock) { double("topic") }
    let(:subscription_mock) { double("subscription") }
    let(:subscriber_mock) { double("subscriber", start: nil, wait!: nil, stop: nil) }
    let(:pubsub_mock) { double("pubsub") }

    before do
      allow(adapter).to receive(:pubsub).and_return(pubsub_mock)
      allow(pubsub_mock).to receive(:subscription).and_return(subscription_mock)
      allow(subscription_mock).to receive(:listen).and_yield(double("message", data: "msg", acknowledge!: nil)).and_return(subscriber_mock)
    end

    it "raises error without block" do
      expect {
        adapter.subscribe("test", "sub1")
      }.to raise_error(ArgumentError, /Block required/)
    end

    it "creates subscription if not exists" do
      allow(pubsub_mock).to receive(:subscription).with("user-events-test-sub").and_return(nil)
      allow(pubsub_mock).to receive(:topic).with("user-events").and_return(topic_mock)
      expect(topic_mock).to receive(:subscribe).with("user-events-test-sub").and_return(subscription_mock)

      adapter.subscribe("user-events", "test-sub") { |msg| }
    end

    it "uses existing subscription" do
      expect(pubsub_mock).to receive(:subscription).with("user-events-test-sub").and_return(subscription_mock)
      expect(topic_mock).not_to receive(:subscribe)

      adapter.subscribe("user-events", "test-sub") { |msg| }
    end

    it "passes options through to GCP listener" do
      expect(subscription_mock).to receive(:listen).with(
        threads: {callback: 16},
        streams: 4
      ).and_return(subscriber_mock)

      adapter.subscribe("test", "sub1", threads: 16, streams: 4) { |msg| }
    end

    it "passes no options by default" do
      expect(subscription_mock).to receive(:listen).with(
        no_args
      ).and_return(subscriber_mock)

      adapter.subscribe("test", "sub1") { |msg| }
    end

    it "calls block with message data" do
      received = []
      message_mock = double("message", data: "test-message", acknowledge!: nil, message_id: "msg-123")

      allow(subscription_mock).to receive(:listen) do |**options, &block|
        block.call(message_mock)
        subscriber_mock
      end

      adapter.subscribe("test", "sub1") do |msg|
        received << msg
      end

      expect(received).to eq(["test-message"])
    end

    it "acknowledges message after processing" do
      message_mock = double("message", data: "msg", message_id: "123")
      expect(message_mock).to receive(:acknowledge!)

      allow(subscription_mock).to receive(:listen) do |**options, &block|
        block.call(message_mock)
        subscriber_mock
      end

      adapter.subscribe("test", "sub1") { |msg| }
    end

    it "logs errors but doesn't crash on processing failure" do
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)

      message_mock = double("message", data: "msg", message_id: "123", acknowledge!: nil)

      allow(subscription_mock).to receive(:listen) do |**options, &block|
        block.call(message_mock)
        subscriber_mock
      end

      expect(logger).to receive(:error).with(/Error processing message/)

      expect {
        adapter.subscribe("test", "sub1") { |msg| raise "Processing failed" }
      }.to raise_error("Processing failed")
    end

    it "wraps GCP subscribe errors" do
      allow(pubsub_mock).to receive(:subscription).and_raise(Google::Cloud::Error, "Auth failed")

      expect {
        adapter.subscribe("test", "sub1") { |msg| }
      }.to raise_error(Joist::Events::AdapterError, /GCP Pub\/Sub subscribe error/)
    end
  end

  describe "#stop" do
    it "stops the subscriber if present" do
      subscriber_mock = double("subscriber", stop: nil)
      adapter.instance_variable_set(:@subscriber, subscriber_mock)

      expect(subscriber_mock).to receive(:stop)

      adapter.stop
    end

    it "does not raise if no subscriber" do
      expect { adapter.stop }.not_to raise_error
    end
  end

  describe "#healthy?" do
    it "returns true if pubsub client is healthy" do
      expect(adapter.pubsub).to receive(:project_id).and_return("test-project")

      expect(adapter.healthy?).to be true
    end

    it "returns false if pubsub raises error" do
      allow(adapter.pubsub).to receive(:project_id).and_raise(StandardError)

      expect(adapter.healthy?).to be false
    end
  end
end

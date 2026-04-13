# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Adapters::Base do
  let(:adapter) { described_class.new }

  describe ".new" do
    it "accepts options" do
      adapter = described_class.new(foo: "bar")

      expect(adapter.options).to eq(foo: "bar")
    end

    it "defaults to empty options" do
      expect(adapter.options).to eq({})
    end
  end

  describe "#publish" do
    it "raises NotImplementedError" do
      expect {
        adapter.publish("test-topic", "message")
      }.to raise_error(NotImplementedError, /must implement #publish/)
    end
  end

  describe "#subscribe" do
    it "raises NotImplementedError" do
      expect {
        adapter.subscribe("test-topic", "subscriber") { |msg| }
      }.to raise_error(NotImplementedError, /must implement #subscribe/)
    end
  end

  describe "#stop" do
    it "does not raise error" do
      expect { adapter.stop }.not_to raise_error
    end
  end

  describe "#healthy?" do
    it "returns true by default" do
      expect(adapter.healthy?).to be true
    end
  end

  describe "custom adapter" do
    let(:custom_adapter) do
      Class.new(described_class) do
        def publish(topic, message)
          @published ||= []
          @published << {topic: topic, message: message}
          true
        end

        def subscribe(topic, subscriber_name, options = {}, &block)
          @subscribed ||= []
          @subscribed << {topic: topic, name: subscriber_name, block: block}
        end

        attr_reader :published, :subscribed
      end.new
    end

    it "can implement publish" do
      result = custom_adapter.publish("test", "msg")

      expect(result).to be true
      expect(custom_adapter.published).to eq([{topic: "test", message: "msg"}])
    end

    it "can implement subscribe" do
      block = proc { |msg| }

      custom_adapter.subscribe("test", "sub1", &block)

      expect(custom_adapter.subscribed.size).to eq(1)
      expect(custom_adapter.subscribed.first[:topic]).to eq("test")
      expect(custom_adapter.subscribed.first[:name]).to eq("sub1")
    end
  end
end

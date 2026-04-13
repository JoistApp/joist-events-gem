# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Publisher do
  before do
    Joist::Events.configure do |config|
      config.register_adapter(:memory)
      config.default_adapter = :memory
      config.serializer = :json
    end
  end

  describe ".new" do
    context "when adapter is configured" do
      it "creates publisher with adapter" do
        publisher = described_class.new("user-events")

        expect(publisher.topic).to eq("user-events")
        expect(publisher.adapter_name).to eq(:memory)
      end
    end

    xit "creates a publisher for a topic" do
      publisher = described_class.new("user-events")

      expect(publisher.topic).to eq("user-events")
      expect(publisher.adapter_name).to eq(:gcp)
    end

    xit "uses specified adapter if provided" do
      Joist::Events.configuration.register_adapter(:amazon_mq, host: "localhost")
      publisher = described_class.new("user-events", adapter: :amazon_mq)

      expect(publisher.adapter_name).to eq(:amazon_mq)
    end

    xit "uses default adapter if not specified" do
      publisher = described_class.new("user-events")

      expect(publisher.adapter_name).to eq(:gcp)
    end
  end

  describe "#publish" do
    # These tests will be skipped until Phase 3-5 are complete
    # They define the contract that must be implemented

    xit "publishes a hash payload" do
      publisher = described_class.new("user-events")
      payload = {user_id: 123, event: "user.created"}

      result = publisher.publish(payload)

      expect(result).to be true
    end

    xit "publishes a Message object" do
      publisher = described_class.new("user-events")
      message = Joist::Events::Message.new(
        topic: "user-events",
        payload: {user_id: 123}
      )

      result = publisher.publish(message)

      expect(result).to be true
    end

    xit "creates Message from hash payload" do
      publisher = described_class.new("user-events")
      payload = {user_id: 123}

      expect(Joist::Events::Message).to receive(:new).with(
        topic: "user-events",
        payload: payload,
        attributes: {}
      ).and_call_original

      publisher.publish(payload)
    end

    xit "passes attributes to Message creation" do
      publisher = described_class.new("user-events")
      payload = {user_id: 123}
      attributes = {priority: "high"}

      expect(Joist::Events::Message).to receive(:new).with(
        topic: "user-events",
        payload: payload,
        attributes: attributes
      ).and_call_original

      publisher.publish(payload, attributes: attributes)
    end

    xit "raises PublishError on failure" do
      publisher = described_class.new("user-events")
      # Mock adapter to raise error
      allow_any_instance_of(Joist::Events::Adapters::Base).to receive(:publish)
        .and_raise(StandardError, "Connection failed")

      expect {
        publisher.publish({user_id: 123})
      }.to raise_error(Joist::Events::PublishError, /Failed to publish message: Connection failed/)
    end

    xit "logs successful publish" do
      publisher = described_class.new("user-events")
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)

      expect(logger).to receive(:debug).with(/Published message/)

      publisher.publish({user_id: 123})
    end

    xit "logs errors" do
      publisher = described_class.new("user-events")
      logger = double("logger")
      allow(Joist::Events.configuration).to receive(:logger).and_return(logger)
      allow_any_instance_of(Joist::Events::Adapters::Base).to receive(:publish)
        .and_raise(StandardError, "Connection failed")

      expect(logger).to receive(:error).with(/Failed to publish message/)

      expect { publisher.publish({user_id: 123}) }.to raise_error(Joist::Events::PublishError)
    end
  end

  describe "#publish_batch" do
    xit "publishes multiple messages" do
      publisher = described_class.new("user-events")
      messages = [
        {user_id: 123, event: "user.created"},
        {user_id: 124, event: "user.created"}
      ]

      count = publisher.publish_batch(messages)

      expect(count).to eq(2)
    end

    xit "returns count of successful publishes" do
      publisher = described_class.new("user-events")
      messages = [{user_id: 123}, {user_id: 124}, {user_id: 125}]

      # Mock one failure
      call_count = 0
      allow_any_instance_of(Joist::Events::Adapters::Base).to receive(:publish) do
        call_count += 1
        raise StandardError if call_count == 2
        true
      end

      count = publisher.publish_batch(messages)

      expect(count).to eq(2) # 2 successful, 1 failed
    end
  end

  describe "#dual_write?" do
    xit "returns false when dual-write not configured" do
      publisher = described_class.new("user-events")

      expect(publisher.dual_write?).to be false
    end

    xit "returns true when dual-write configured" do
      Joist::Events.configuration.register_adapter(:amazon_mq, host: "localhost")
      Joist::Events.configuration.enable_dual_write(:gcp, :amazon_mq)

      publisher = described_class.new("user-events")

      expect(publisher.dual_write?).to be true
    end
  end

  describe "dual-write mode" do
    before do
      Joist::Events.configuration.register_adapter(:amazon_mq, host: "localhost")
      Joist::Events.configuration.enable_dual_write(:gcp, :amazon_mq)
    end

    xit "publishes to all configured adapters" do
      publisher = described_class.new("user-events")
      gcp_adapter = double("gcp_adapter")
      mq_adapter = double("mq_adapter")

      allow(publisher).to receive(:build_adapter).with(:gcp).and_return(gcp_adapter)
      allow(publisher).to receive(:build_adapter).with(:amazon_mq).and_return(mq_adapter)

      expect(gcp_adapter).to receive(:publish).with("user-events", anything)
      expect(mq_adapter).to receive(:publish).with("user-events", anything)

      publisher.publish({user_id: 123})
    end

    xit "returns true if all adapters succeed" do
      publisher = described_class.new("user-events")

      # Mock all adapters to succeed
      allow_any_instance_of(Joist::Events::Adapters::Base).to receive(:publish)
        .and_return(true)

      result = publisher.publish({user_id: 123})

      expect(result).to be true
    end

    xit "raises error if any adapter fails" do
      publisher = described_class.new("user-events")

      # Mock one adapter to fail
      call_count = 0
      allow_any_instance_of(Joist::Events::Adapters::Base).to receive(:publish) do
        call_count += 1
        raise StandardError, "Adapter failed" if call_count == 2
        true
      end

      expect {
        publisher.publish({user_id: 123})
      }.to raise_error(Joist::Events::PublishError)
    end
  end
end

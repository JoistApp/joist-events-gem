# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Configuration do
  describe "initialization" do
    it "has default values" do
      config = described_class.new

      expect(config.default_adapter).to eq(:gcp)
      expect(config.adapters).to eq({})
      expect(config.serializer).to eq(:json)
      expect(config.middleware).to eq([])
      expect(config.legacy_mode).to be false
      expect(config.use_gcp).to be true
    end

    it "has a logger" do
      config = described_class.new
      expect(config.logger).not_to be_nil
    end
  end

  describe "#register_adapter" do
    it "registers an adapter with configuration" do
      config = described_class.new
      config.register_adapter(:gcp, project_id: "test-project")

      expect(config.adapters[:gcp]).to eq(project_id: "test-project")
    end

    it "converts string keys to symbols" do
      config = described_class.new
      config.register_adapter("amazon_mq", host: "localhost")

      expect(config.adapters[:amazon_mq]).to eq(host: "localhost")
    end
  end

  describe "#enable_dual_write" do
    it "enables dual-write mode for multiple adapters" do
      config = described_class.new
      config.enable_dual_write(:gcp, :amazon_mq)

      expect(config.dual_write?).to be true
      expect(config.dual_write_adapters).to eq([:gcp, :amazon_mq])
    end

    it "returns empty array when dual-write not enabled" do
      config = described_class.new
      expect(config.dual_write_adapters).to eq([])
    end
  end

  describe "#validate!" do
    it "raises error when no adapters configured" do
      config = described_class.new

      expect { config.validate! }.to raise_error(
        Joist::Events::ConfigurationError,
        "No adapters configured"
      )
    end

    it "raises error when default adapter not in configured adapters" do
      config = described_class.new
      config.register_adapter(:amazon_mq, host: "localhost")
      config.default_adapter = :gcp

      expect { config.validate! }.to raise_error(
        Joist::Events::ConfigurationError,
        "Default adapter not configured"
      )
    end

    it "returns true when configuration is valid" do
      config = described_class.new
      config.register_adapter(:gcp, project_id: "test")

      expect(config.validate!).to be true
    end
  end
end

RSpec.describe Joist::Events do
  describe ".configure" do
    it "yields configuration object" do
      expect do |b|
        described_class.configure do |config|
          b.to_proc.call(config)
          config.register_adapter(:gcp, project_id: "test")
        end
      end.to yield_with_args(Joist::Events::Configuration)
    end

    it "allows setting configuration values" do
      described_class.configure do |config|
        config.default_adapter = :amazon_mq
        config.register_adapter(:amazon_mq, host: "localhost")
        config.serializer = :avro
        config.middleware = [:retry, :metrics]
      end

      config = described_class.configuration
      expect(config.default_adapter).to eq(:amazon_mq)
      expect(config.serializer).to eq(:avro)
      expect(config.middleware).to eq([:retry, :metrics])
    end

    it "validates configuration after yielding" do
      expect do
        described_class.configure do |config|
          config.default_adapter = :gcp
          # Not registering adapter - should fail validation
        end
      end.to raise_error(Joist::Events::ConfigurationError)
    end
  end

  describe ".configuration" do
    it "returns singleton configuration" do
      config1 = described_class.configuration
      config2 = described_class.configuration

      expect(config1).to be(config2)
    end
  end

  describe ".reset_configuration!" do
    it "resets configuration to defaults" do
      described_class.configure do |config|
        config.default_adapter = :amazon_mq
        config.register_adapter(:amazon_mq, host: "test")
      end

      described_class.reset_configuration!

      config = described_class.configuration
      expect(config.default_adapter).to eq(:gcp)
      expect(config.adapters).to eq({})
    end
  end
end

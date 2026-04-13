# frozen_string_literal: true

require "spec_helper"

RSpec.describe Joist::Events::Serializers::Base do
  let(:serializer) { described_class.new }
  let(:message) do
    Joist::Events::Message.new(
      topic: "test-topic",
      payload: {user_id: 123}
    )
  end

  describe "#serialize" do
    it "raises NotImplementedError" do
      expect {
        serializer.serialize(message)
      }.to raise_error(NotImplementedError, /must implement #serialize/)
    end
  end

  describe "#deserialize" do
    it "raises NotImplementedError" do
      expect {
        serializer.deserialize('{"topic":"test"}')
      }.to raise_error(NotImplementedError, /must implement #deserialize/)
    end
  end
end

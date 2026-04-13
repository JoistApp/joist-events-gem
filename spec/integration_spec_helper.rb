# frozen_string_literal: true

require "spec_helper"

# Integration test helper
# Tests in spec/integration can be slower and test multiple components together
# These tests verify real behavior without extensive mocking

RSpec.configure do |config|
  # Tag all integration tests
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |metadata|
    metadata[:integration] = true
    metadata[:type] = :integration
  end

  # Integration tests can be slower - no special timeout needed for now
  # Tests handle their own sleep/wait logic

  # Helper to setup test configuration
  config.before(:each, :integration) do
    Joist::Events.configure do |c|
      c.logger = Logger.new(nil) # Quiet logger for tests
      c.register_adapter(:memory, {})
      c.default_adapter = :memory
    end
  end
end

# Helper methods available in integration tests
module IntegrationHelpers
  def create_publisher(topic = "test-topic")
    Joist::Events::Publisher.new(topic)
  end

  def create_memory_adapter
    Joist::Events::Adapters::MemoryAdapter.new({})
  end

  def create_message(payload = {user_id: 123})
    Joist::Events::Message.new(
      topic: "test-topic",
      payload: payload
    )
  end

  def wait_for_messages(adapter, topic, expected_count, timeout: 2)
    start_time = Time.now
    loop do
      return true if adapter.messages_for(topic).count >= expected_count
      return false if Time.now - start_time > timeout
      sleep 0.01
    end
  end
end

RSpec.configure do |config|
  config.include IntegrationHelpers, :integration
end

# frozen_string_literal: true

require "integration_spec_helper"

RSpec.describe "Thread Safety", :integration do
  describe "concurrent publishers" do
    it "handles multiple publishers without message loss" do
      adapter = Joist::Events::Adapters::MemoryAdapter.new({})
      messages_received = []
      mutex = Mutex.new

      # Start subscriber
      subscriber_thread = Thread.new do
        adapter.subscribe("stress-test", "test-subscriber") do |message|
          mutex.synchronize { messages_received << message }
        end
      end

      sleep 0.1

      # Create 10 publisher threads (10 x 100 = 1000 messages)
      publisher_threads = []
      10.times do |thread_id|
        publisher_threads << Thread.new do
          100.times do |msg_id|
            payload = %({"thread_id": #{thread_id}, "message_id": #{msg_id}})
            adapter.publish("stress-test", payload)
          end
        end
      end

      # Wait for all publishers
      publisher_threads.each(&:join)

      # Wait for messages to be processed
      sleep 1

      adapter.stop
      subscriber_thread.kill

      expect(messages_received.count).to eq(1000)
    end
  end

  describe "multiple subscribers" do
    it "delivers messages to all subscribers" do
      adapter = Joist::Events::Adapters::MemoryAdapter.new({})
      subscriber_counts = Hash.new(0)
      subscriber_mutex = Mutex.new

      # Start 5 subscribers
      subscriber_threads = []
      5.times do |sub_id|
        subscriber_threads << Thread.new do
          adapter.subscribe("multi-sub-test", "subscriber-#{sub_id}") do |message|
            subscriber_mutex.synchronize { subscriber_counts[sub_id] += 1 }
          end
        end
      end

      sleep 0.1

      # Publish 500 messages
      500.times do |i|
        payload = %({"message_id": #{i}})
        adapter.publish("multi-sub-test", payload)
      end

      # Wait for processing
      sleep 1

      adapter.stop
      subscriber_threads.each(&:kill)

      # Each subscriber should receive all 500 messages
      total_received = subscriber_counts.values.sum
      expect(total_received).to eq(500 * 5) # 500 messages × 5 subscribers
      expect(subscriber_counts.values).to all(eq(500))
    end
  end

  describe "concurrent subscribe and publish (race condition test)" do
    it "handles simultaneous subscribers and publishers" do
      adapter = Joist::Events::Adapters::MemoryAdapter.new({})
      race_messages = []
      race_mutex = Mutex.new

      threads = []

      # 3 subscribers
      3.times do |sub_id|
        threads << Thread.new do
          adapter.subscribe("race-test", "sub-#{sub_id}") do |message|
            race_mutex.synchronize { race_messages << message }
          end
        end
      end

      # 3 publishers (start immediately)
      3.times do |pub_id|
        threads << Thread.new do
          100.times do |i|
            payload = %({"pub_id": #{pub_id}, "msg_id": #{i}})
            adapter.publish("race-test", payload)
          end
        end
      end

      # Let them race
      sleep 1

      adapter.stop
      threads.each(&:kill)

      # 3 publishers × 100 messages × 3 subscribers = 900
      expected_total = 3 * 100 * 3
      expect(race_messages.count).to eq(expected_total)
    end
  end

  describe "adapter internal thread safety" do
    it "handles concurrent operations without errors" do
      adapter = Joist::Events::Adapters::MemoryAdapter.new({})
      errors = []
      error_mutex = Mutex.new

      # Hammer the adapter from multiple threads
      stress_threads = []
      10.times do |thread_id|
        stress_threads << Thread.new do
          # Mix of operations
          50.times do |i|
            adapter.publish("stress", %({"thread": #{thread_id}, "msg": #{i}}))

            # Randomly start/stop subscribers
            if i % 10 == 0
              sub = Thread.new do
                adapter.subscribe("stress", "temp-#{thread_id}-#{i}") { |msg| }
              rescue => e
                error_mutex.synchronize { errors << e }
              end
              sleep 0.001
              sub.kill
            end
          end
        rescue => e
          error_mutex.synchronize { errors << e }
        end
      end

      stress_threads.each(&:join)
      adapter.stop

      expect(errors).to be_empty
    end
  end

  describe "memory adapter mutex protection" do
    it "protects shared state with mutex" do
      adapter = Joist::Events::Adapters::MemoryAdapter.new({})

      # Verify adapter uses mutex for thread safety
      expect(adapter.instance_variable_get(:@mutex)).to be_a(Mutex)

      # Test that concurrent access doesn't corrupt state
      threads = []
      100.times do
        threads << Thread.new do
          10.times { |i| adapter.publish("test", %({"i": #{i}})) }
        end
      end

      threads.each(&:join)

      # Should have exactly 1000 messages (100 threads × 10 messages)
      expect(adapter.messages_for("test").count).to eq(1000)
    end
  end
end

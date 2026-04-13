# frozen_string_literal: true

# Example: Background Job Integration (RECOMMENDED for Rails web processes)
#
# This pattern allows subscribers to run in Rails web processes safely
# by immediately delegating all processing to background job queues.
#
# Benefits:
# - Minimal memory footprint in subscriber
# - No ActiveRecord in subscriber threads
# - Leverage existing job infrastructure (Sidekiq, GoodJob, etc.)
# - Proper connection management via job workers
# - Job retry/failure handling

# ============================================================================
# STEP 1: Lightweight subscriber that delegates to jobs
# ============================================================================

class UserEventsSubscriber < Joist::Events::Subscriber
  topic "user-events"
  subscriber_name "user-service"

  def consume!(message)
    # Immediately delegate to background job
    # NO Rails/ActiveRecord code here
    # Message deserialization already done by framework
    ProcessUserEventJob.perform_async(message.to_h)
  rescue => e
    # Log errors but don't crash subscriber
    Rails.logger.error("Failed to enqueue job: #{e.message}")
    raise # Let adapter handle retry
  end
end

# ============================================================================
# STEP 2: Background job that does actual processing
# ============================================================================

# Using Sidekiq
class ProcessUserEventJob
  include Sidekiq::Worker

  # Configure retries and error handling
  sidekiq_options retry: 5, dead: true

  def perform(message_data)
    # Reconstruct message
    message = Joist::Events::Message.from_h(message_data.deep_symbolize_keys)

    # Now safe to use ActiveRecord - in job worker process
    case message.payload[:event]
    when "user.created"
      handle_user_created(message)
    when "user.updated"
      handle_user_updated(message)
    else
      Rails.logger.warn("Unknown event: #{message.payload[:event]}")
    end
  end

  private

  def handle_user_created(message)
    user = User.find(message.payload[:user_id])
    # Process user creation...
    Rails.logger.info("Processed user.created for #{user.id}")
  end

  def handle_user_updated(message)
    user = User.find(message.payload[:user_id])
    # Process user update...
    Rails.logger.info("Processed user.updated for #{user.id}")
  end
end

# Using GoodJob (alternative)
class ProcessUserEventJob < ApplicationJob
  queue_as :events

  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  def perform(message_data)
    Joist::Events::Message.from_h(message_data.deep_symbolize_keys)
    # Process message...
  end
end

# ============================================================================
# STEP 3: Configuration
# ============================================================================

# config/initializers/joist_events.rb
Joist::Events.configure do |config|
  # Minimal thread configuration for job delegation pattern
  config.register_adapter(
    :gcp,
    project_id: ENV.fetch("GCP_PROJECT_ID"),
    threads: 2, # Minimal - just receives and enqueues
    streams: 1
  )
  config.default_adapter = :gcp
  config.serializer = :json
end

# ============================================================================
# STEP 4: Start subscriber (in web process or separate process)
# ============================================================================

# Option A: In Rails web process (Puma/Unicorn) after_fork hook
# config/puma.rb
on_worker_boot do
  # Start subscriber in each worker
  Thread.new do
    UserEventsSubscriber.new.subscribe!
  end
end

# Option B: Separate subscriber process (better)
# bin/subscribers/user_events
# !/usr/bin/env ruby
require_relative "../../config/environment"

UserEventsSubscriber.new.subscribe!

# ============================================================================
# STEP 5: Procfile for development/deployment
# ============================================================================

# Procfile.dev (for foreman/overmind)
# web: bundle exec puma -C config/puma.rb
# worker: bundle exec sidekiq -C config/sidekiq.yml
# subscriber: bundle exec ruby bin/subscribers/user_events

# ============================================================================
# STEP 6: Testing
# ============================================================================

# spec/subscribers/user_events_subscriber_spec.rb
RSpec.describe UserEventsSubscriber do
  describe "#consume!" do
    it "enqueues job for user.created event" do
      message = Joist::Events::Message.new(
        topic: "user-events",
        payload: {event: "user.created", user_id: 123}
      )

      # Test that job is enqueued
      expect {
        described_class.new.consume!(message)
      }.to change(ProcessUserEventJob.jobs, :size).by(1)

      # Verify job payload
      job = ProcessUserEventJob.jobs.last
      expect(job["args"]).to include(hash_including("event" => "user.created"))
    end
  end
end

# spec/jobs/process_user_event_job_spec.rb
RSpec.describe ProcessUserEventJob do
  describe "#perform" do
    it "processes user.created event" do
      user = create(:user)
      message_data = {
        id: "msg-123",
        topic: "user-events",
        payload: {event: "user.created", user_id: user.id},
        timestamp: Time.current.iso8601,
        attributes: {}
      }

      expect {
        described_class.new.perform(message_data)
      }.not_to raise_error
    end
  end
end

# ============================================================================
# Memory and Performance Characteristics
# ============================================================================

# SUBSCRIBER PROCESS:
# - Memory: ~50-100MB (minimal - just receives messages)
# - Threads: 2-4 (just for receiving, not processing)
# - DB Connections: 1-2 (just for job enqueueing)
# - CPU: Minimal

# JOB WORKER PROCESS:
# - Memory: Depends on job complexity (properly isolated)
# - Threads: Per Sidekiq/GoodJob configuration
# - DB Connections: Per worker pool configuration
# - CPU: Where actual work happens

# SCALING:
# - Scale subscriber processes based on message volume
# - Scale job workers based on processing complexity
# - Independent scaling strategies
# - No connection pool conflicts

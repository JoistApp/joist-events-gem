# Joist Events

Multi-backend event publishing and subscribing for Joist services. Provides abstraction over multiple messaging backends (GCP Pub/Sub, Amazon MQ/RabbitMQ) with middleware support for idempotency, retry, and metrics.

**Status**: ✅ Production Ready (275 tests, 87% coverage)

## Features

- ✅ **Multi-Backend Support**: GCP Pub/Sub, Amazon MQ (RabbitMQ), Memory (testing)
- ✅ **Publisher Acknowledgment**: Wait for broker confirmation before returning
- ✅ **Dual-Write Mode**: Publish to multiple backends simultaneously during migration
- ✅ **Middleware System**: Idempotency, retry, metrics
- ✅ **Thread-Safe**: All adapters use proper synchronization
- ✅ **Pluggable Serializers**: JSON (extensible to Avro, Protobuf)

## Installation

```ruby
# Gemfile
gem 'joist_events'
```

```bash
bundle install
```

## Quick Start

### Configuration

```ruby
# config/initializers/joist_events.rb
Joist::Events.configure do |config|
  config.default_adapter = :gcp
  
  # Register adapters
  config.register_adapter(:gcp, project_id: ENV['GCP_PROJECT_ID'])
  config.register_adapter(:amazon_mq,
    host: ENV['AMAZON_MQ_HOST'],
    port: 5671,
    username: ENV['AMAZON_MQ_USERNAME'],
    password: ENV['AMAZON_MQ_PASSWORD'],
    vhost: '/',
    tls: true
  )
  
  # Optional: Enable dual-write for migration
  config.enable_dual_write(:gcp, :amazon_mq)
end
```

### Publishing

```ruby
# Simple publish
publisher = Joist::Events::Publisher.new('user-events')
message_id = publisher.publish({
  event: 'user.created',
  user_id: 123,
  email: 'user@example.com'
})
# => "msg-12345" (returns message ID by default)

# Fire-and-forget (faster, no ack)
publisher.publish(message, wait_for_ack: false)
# => true
```

### Subscribing

```ruby
# Define subscriber class
class UserCreatedSubscriber < Joist::Events::Subscriber
  topic 'user-events'
  subscriber_name 'user-service'
  
  def consume!(message)
    user_id = message.payload['user_id']
    Rails.logger.info "User #{user_id} created"
  end
end

# Start subscriber (blocking)
UserCreatedSubscriber.new.subscribe!
```

## Publisher Acknowledgment

By default, publishers wait for broker acknowledgment to ensure at-least-once delivery:

```ruby
# Default: Safe (waits for broker ack)
message_id = publisher.publish(message)
# => "msg-12345"

# Fast: Fire-and-forget
success = publisher.publish(message, wait_for_ack: false)
# => true
```

**How it works:**
- **GCP Pub/Sub**: Returns message ID from successful publish
- **Amazon MQ**: Uses RabbitMQ publisher confirms
- **Memory**: Returns synthetic message ID for testing

## Thread Safety & Concurrency

All adapters are thread-safe:
- **Memory**: Uses `Mutex` for thread-safe operations
- **GCP Pub/Sub**: Delegates to Google's thread-safe client
- **Amazon MQ**: Uses Bunny gem's thread-safe connection management

### Recommended Patterns for Rails

**Option 1: Separate Processes (BEST)**
```ruby
# bin/subscribers/user_events
UserEventsSubscriber.new.subscribe!
```

**Option 2: Background Job Delegation**
```ruby
class UserEventsSubscriber < Joist::Events::Subscriber
  def consume!(message)
    ProcessUserEventJob.perform_async(message.to_h)
  end
end
```

### Concurrency Control

Concurrency is controlled by the message broker, not this gem:
- **GCP Pub/Sub**: Pass `threads:` and `streams:` options
- **Amazon MQ**: Configure `prefetch:` and consumer count
- **Memory**: Synchronous delivery

## Project Structure

```
joist-events-gem/
├── lib/
│   └── joist/events/
│       ├── adapters/          # GCP, Amazon MQ, Memory
│       ├── middleware/        # Idempotency, Retry, Metrics
│       ├── serializers/       # JSON
│       ├── publisher.rb
│       ├── subscriber.rb
│       └── message.rb
├── spec/
│   ├── unit/                  # Fast, isolated tests (253)
│   └── integration/           # Multi-component tests (22)
└── examples/                  # Usage examples
```

## Testing

### Run Tests

```bash
# Unit tests only (fast, < 1s)
bundle exec rake spec

# Integration tests (slower, ~5s)
bundle exec rake spec_integration

# All tests
bundle exec rake spec_all

# Run with linter (default)
bundle exec rake
```

### Test Organization

- **Unit Tests** (`spec/unit/`) - Fast, mocked, isolated component tests
- **Integration Tests** (`spec/integration/`) - Slower, real workflow tests
  - `local_integration_spec.rb` - Basic pub/sub workflows
  - `publisher_acknowledgment_spec.rb` - Ack feature verification
  - `thread_safety_spec.rb` - Concurrent operation tests

### Writing Tests

**Unit Test:**
```ruby
# spec/unit/my_component_spec.rb
require "spec_helper"

RSpec.describe MyComponent do
  it "does something" do
    component = described_class.new
    expect(component.method_name).to eq("expected")
  end
end
```

**Integration Test:**
```ruby
# spec/integration/my_feature_spec.rb
require "integration_spec_helper"

RSpec.describe "My Feature", :integration do
  it "works end-to-end" do
    publisher = create_publisher("test-topic")
    result = publisher.publish({data: "test"})
    expect(result).to be_truthy
  end
end
```

## Middleware

### Built-in Middleware

**Idempotency:**
```ruby
# Prevents duplicate message processing
middleware = Joist::Events::Middleware::Idempotency.new(
  storage: Joist::Events::Middleware::MemoryIdempotencyStorage.new,
  ttl: 3600  # 1 hour
)
```

**Retry:**
```ruby
# Automatic retry with exponential backoff
middleware = Joist::Events::Middleware::Retry.new(
  max_attempts: 3,
  base_delay: 0.1,
  backoff_factor: 2.0
)
```

**Metrics:**
```ruby
# Track publish/subscribe metrics
middleware = Joist::Events::Middleware::Metrics.new(
  backend: Joist::Events::Middleware::MemoryMetricsBackend.new
)
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                  Application Code                    │
└──────────────────────┬──────────────────────────────┘
                       │
         ┌─────────────┴─────────────┐
         │  Publisher / Subscriber    │
         └─────────────┬─────────────┘
                       │
         ┌─────────────┴─────────────┐
         │   Middleware Chain         │
         │ (Idempotency, Retry, etc) │
         └─────────────┬─────────────┘
                       │
         ┌─────────────┴─────────────┐
         │      Serializer            │
         └─────────────┬─────────────┘
                       │
         ┌─────────────┴─────────────┐
         │       Adapter              │
         ├───────────┬─────────┬─────┤
         │    GCP    │ AmazonMQ│Memory│
         └───────────┴─────────┴─────┘
```

## Migration from Legacy System

Use dual-write mode to safely migrate between message brokers:

```ruby
# Step 1: Enable dual-write
Joist::Events.configure do |config|
  config.enable_dual_write(:gcp, :amazon_mq)
end

# Step 2: Verify both systems working

# Step 3: Switch consumers to new broker

# Step 4: Remove dual-write, use single adapter
```

## Advanced Usage

### Custom Adapters

Implement `Joist::Events::Adapters::Base`:

```ruby
class MyAdapter < Joist::Events::Adapters::Base
  def publish(topic, message, options = {})
    # Implementation
    true
  end
  
  def subscribe(topic, subscriber_name, options = {}, &block)
    # Implementation
  end
end
```

### Custom Middleware

Implement `Joist::Events::Middleware::Base`:

```ruby
class MyMiddleware < Joist::Events::Middleware::Base
  def call(message, &block)
    # Pre-processing
    result = block.call
    # Post-processing
    result
  end
end
```

## Performance

**Memory Adapter (1000 messages):**
- With ack: ~1.5M msg/s
- Without ack: ~4.4M msg/s

**GCP Pub/Sub / Amazon MQ:**
- With ack: Limited by network latency (1-50ms per message)
- Without ack: Fire-and-forget (no wait)

**Recommendation:** Use `wait_for_ack: true` (default) for critical messages, `false` for high-volume logging.

## Troubleshooting

### Connection Issues

**GCP Pub/Sub:**
```ruby
# Check credentials
adapter.healthy?

# Enable emulator for testing
config.register_adapter(:gcp, 
  project_id: "test-project",
  emulator_host: "localhost:8085"
)
```

**Amazon MQ:**
```ruby
# Verify connection
adapter.healthy?

# Check SSL/TLS settings
config.register_adapter(:amazon_mq,
  host: "broker.mq.amazonaws.com",
  port: 5671,
  tls: true,
  verify_peer: true
)
```

### Thread Safety

All adapters are thread-safe. Run integration tests to verify:

```bash
bundle exec rspec spec/integration/thread_safety_spec.rb
```

## Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/my-feature`)
3. Write tests first (TDD)
4. Implement feature
5. Ensure tests pass (`bundle exec rake`)
6. Submit pull request

## License

MIT License. See LICENSE.txt for details.

## Examples

See the [examples/](examples/) directory for usage patterns:
- `background_job_integration.rb` - Sidekiq integration
- `bin/subscriber_process` - Standalone subscriber script

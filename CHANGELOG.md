# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-04-13

### Changed
- Updated dependency version ranges for better compatibility
  - `activesupport`: `~> 7.2.0` → `>= 7.2, < 8.2` (now supports Rails 8.x)
  - `google-cloud-pubsub`: `~> 2.9, >= 2.9.1` → `>= 2.9.1, < 4.0` (now supports v3.x)
  - `bunny`: `~> 2.22` → `>= 2.22, < 4.0` (now supports v3.x)
  - `fabrication`: `~> 2.31` → `~> 3.0` (test dependency)

## [1.0.0] - 2026-04-13

### Added
- **Multi-Backend Support**: GCP Pub/Sub, Amazon MQ (RabbitMQ), Memory adapters
- **Publisher Acknowledgment**: Wait for broker confirmation with `wait_for_ack` option (default: true)
  - GCP: Returns message ID from Pub/Sub
  - Amazon MQ: Uses RabbitMQ publisher confirms
  - Memory: Returns synthetic message ID
- **Dual-Write Mode**: Publish to multiple backends simultaneously for seamless migration
- **Thread-Safe Adapters**: All adapters use proper synchronization (Mutex, thread-safe clients)
- **Middleware System**: Pluggable middleware chain
  - Idempotency: Prevent duplicate message processing
  - Retry: Automatic retry with exponential backoff
  - Metrics: Performance tracking and monitoring
- **Message System**: Structured message format with metadata and timestamps
- **Serializers**: JSON serialization (extensible to Avro, Protobuf)
- **Comprehensive Testing**: 275 tests (253 unit, 22 integration) with 89% coverage

### Features
- Publisher interface with acknowledgment control
- Subscriber base class with automatic message deserialization
- Configuration system with multiple adapter registration
- Health check support for all adapters
- Automatic message ID generation
- ISO8601 timestamp handling
- Background job integration patterns

### Documentation
- Complete README with quick start, examples, and troubleshooting
- Integration test examples
- Thread safety documentation
- Migration guide for dual-write pattern

### Performance
- Memory adapter: ~1.5M-4.4M msg/s depending on ack mode
- GCP Pub/Sub: Network-limited with optional ack
- Amazon MQ: RabbitMQ performance with publisher confirms

### Breaking Changes
- No backward compatibility with legacy `joist_pubsub` gem
- Use dual-write mode for migration from legacy systems

[1.0.1]: https://github.com/JoistApp/joist-events-gem/releases/tag/v1.0.1
[1.0.0]: https://github.com/JoistApp/joist-events-gem/releases/tag/v1.0.0

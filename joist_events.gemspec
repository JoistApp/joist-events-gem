# frozen_string_literal: true

lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "joist/events/version"

Gem::Specification.new do |spec|
  spec.name = "joist_events"
  spec.version = Joist::Events::VERSION
  spec.authors = ["Joist, Inc."]
  spec.email = ["infra@joist.com"]

  spec.summary = "Multi-backend event publishing and subscribing for Joist services"
  spec.description = "Provides abstraction over multiple messaging backends (GCP Pub/Sub, Amazon MQ/RabbitMQ) with middleware support for idempotency, retry, and metrics. Features publisher acknowledgment, thread-safe adapters, and dual-write mode for seamless migration."
  spec.homepage = "https://github.com/JoistApp/joist-events-gem"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.7"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/JoistApp/joist-events-gem"
  spec.metadata["changelog_uri"] = "https://github.com/JoistApp/joist-events-gem/blob/main/CHANGELOG.md"

  spec.files = Dir["{lib,bin}/**/*", "README.md", "LICENSE.txt", "CHANGELOG.md"]
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{\Abin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "activesupport", "~> 7.2.0"

  # Backend adapters (optional, load as needed)
  spec.add_dependency "google-cloud-pubsub", "~> 2.9", ">= 2.9.1" # GCP adapter
  spec.add_dependency "bunny", "~> 2.22" # RabbitMQ/Amazon MQ adapter

  # Serialization
  spec.add_dependency "multi_json", "~> 1.15"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.6"
  spec.add_development_dependency "standard", "~> 1.31"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "webmock", "~> 3.19"
  spec.add_development_dependency "fabrication", "~> 3.0"
  spec.add_development_dependency "faker", "~> 3.2"
  spec.add_development_dependency "rake", "~> 13.0"
end

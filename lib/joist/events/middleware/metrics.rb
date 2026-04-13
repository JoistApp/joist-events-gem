# frozen_string_literal: true

module Joist
  module Events
    module Middleware
      # Metrics middleware for tracking message processing
      #
      # Collects timing, success/failure counts, and custom metrics.
      # Requires a metrics backend to report metrics.
      #
      # @example With StatsD backend
      #   backend = StatsDMetricsBackend.new(statsd: Statsd.new)
      #   middleware = Metrics.new(backend: backend)
      #
      # @example With memory backend (testing)
      #   middleware = Metrics.new(backend: MemoryMetricsBackend.new)
      class Metrics < Base
        attr_reader :backend, :namespace

        # Create metrics middleware
        #
        # @param backend [Object] metrics backend with #increment(name, tags), #timing(name, duration, tags)
        # @param namespace [String] prefix for metric names
        def initialize(backend:, namespace: "joist.events")
          @backend = backend
          @namespace = namespace

          validate_backend!
        end

        # Process message with metrics collection
        #
        # @param message [Message] message to process
        # @yield Block to execute while collecting metrics
        # @return Result from block
        def call(message, &block)
          start_time = Time.now

          result = block.call

          duration = (Time.now - start_time) * 1000 # milliseconds
          record_success(message, duration)

          result
        rescue => e
          duration = (Time.now - start_time) * 1000
          record_failure(message, duration, e)
          raise
        end

        private

        def validate_backend!
          unless backend.respond_to?(:increment) && backend.respond_to?(:timing)
            raise ArgumentError, "Backend must implement #increment and #timing"
          end
        end

        def record_success(message, duration)
          tags = build_tags(message)

          backend.increment("#{namespace}.processed", tags)
          backend.increment("#{namespace}.success", tags)
          backend.timing("#{namespace}.duration", duration, tags)
        end

        def record_failure(message, duration, error)
          base_tags = build_tags(message)
          failure_tags = base_tags.merge(error_class: error.class.name)

          backend.increment("#{namespace}.processed", base_tags)
          backend.increment("#{namespace}.failure", failure_tags)
          backend.timing("#{namespace}.duration", duration, base_tags)
        end

        def build_tags(message)
          {
            topic: message.topic,
            message_id: message.id
          }
        end
      end

      # Memory-based metrics backend (for testing only)
      class MemoryMetricsBackend
        attr_reader :counters, :timings

        def initialize
          @counters = Hash.new(0)
          @timings = []
        end

        def increment(name, tags = {})
          key = build_key(name, tags)
          @counters[key] += 1
        end

        def timing(name, duration, tags = {})
          @timings << {name: name, duration: duration, tags: tags}
        end

        def clear
          @counters.clear
          @timings.clear
        end

        def counter_value(name, tags = {})
          key = build_key(name, tags)
          @counters[key]
        end

        private

        def build_key(name, tags)
          # Sort tags by key to ensure consistent hash
          sorted_tags = tags.sort_by { |k, v| k.to_s }.to_h
          [name, sorted_tags]
        end
      end
    end
  end
end

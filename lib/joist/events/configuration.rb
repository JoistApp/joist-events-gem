# frozen_string_literal: true

module Joist
  module Events
    # Central configuration for Joist::Events
    #
    # Example:
    #   Joist::Events.configure do |config|
    #     config.default_adapter = :gcp
    #     config.adapters[:gcp] = { project_id: "my-project" }
    #     config.adapters[:amazon_mq] = { host: "broker.amazonaws.com", port: 5671 }
    #     config.serializer = :json
    #     config.middleware = [:idempotency, :retry, :metrics]
    #   end
    class Configuration
      attr_accessor :default_adapter, :adapters, :serializer, :middleware, :logger

      # Backward compatibility flags
      attr_accessor :legacy_mode, :use_gcp

      def initialize
        @default_adapter = :gcp
        @adapters = {}
        @serializer = :json
        @middleware = []
        @logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
        @legacy_mode = false
        @use_gcp = true
      end

      # Register an adapter configuration
      #
      # @param name [Symbol] adapter name (:gcp, :amazon_mq, :memory)
      # @param config [Hash] adapter-specific configuration
      def register_adapter(name, config = {})
        @adapters[name.to_sym] = config
      end

      # Enable dual-write mode (publish to multiple backends)
      #
      # @param adapters [Array<Symbol>] list of adapter names to publish to
      def enable_dual_write(*adapters)
        @dual_write_adapters = adapters
      end

      # Get dual-write adapters
      #
      # @return [Array<Symbol>] list of adapters for dual-write
      def dual_write_adapters
        @dual_write_adapters || []
      end

      # Check if dual-write is enabled
      #
      # @return [Boolean]
      def dual_write?
        !dual_write_adapters.empty?
      end

      # Validate configuration
      #
      # @raise [ConfigurationError] if configuration is invalid
      def validate!
        raise ConfigurationError, "No adapters configured" if @adapters.empty?
        raise ConfigurationError, "Default adapter not configured" unless @adapters.key?(@default_adapter)

        true
      end
    end

    class ConfigurationError < StandardError; end

    class << self
      attr_writer :configuration

      # Get current configuration
      #
      # @return [Configuration]
      def configuration
        @configuration ||= Configuration.new
      end

      # Configure Joist::Events
      #
      # @yield [Configuration] configuration object
      def configure
        yield(configuration)
        configuration.validate!
      end

      # Reset configuration (useful for testing)
      def reset_configuration!
        @configuration = Configuration.new
      end
    end
  end
end

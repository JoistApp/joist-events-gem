# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Unit tests (fast, no external dependencies)
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = "spec/unit/**/*_spec.rb"
  t.rspec_opts = "--tag ~integration"
end

# Integration tests (slower, may test multiple components)
RSpec::Core::RakeTask.new(:spec_integration) do |t|
  t.pattern = "spec/integration/**/*_spec.rb"
  t.rspec_opts = "--tag integration"
end

# All tests
RSpec::Core::RakeTask.new(:spec_all) do |t|
  t.pattern = "spec/**/*_spec.rb"
end

require "standard/rake"

task test: :spec
task test_integration: :spec_integration
task test_all: :spec_all

task default: %i[spec standard:fix]

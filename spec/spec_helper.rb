# frozen_string_literal: true

require "bundler/setup"
require "leann"
require "fileutils"
require "net/http"

# Check Ollama BEFORE WebMock is loaded
OLLAMA_AVAILABLE = begin
  uri = URI.parse("http://localhost:11434/api/version")
  response = Net::HTTP.get_response(uri)
  response.code == "200"
rescue StandardError
  false
end

require "webmock/rspec"
require "vcr"

# VCR configuration for recording HTTP interactions
VCR.configure do |config|
  config.cassette_library_dir = "spec/cassettes"
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Allow real connections when recording
  config.allow_http_connections_when_no_cassette = true

  # Ignore localhost (Ollama) - always allow real connections
  config.ignore_localhost = true

  # Filter sensitive data
  config.filter_sensitive_data("<OPENAI_API_KEY>") { ENV.fetch("OPENAI_API_KEY", nil) }
  config.filter_sensitive_data("<OPENROUTER_API_KEY>") { ENV.fetch("OPENROUTER_API_KEY", nil) }
  config.filter_sensitive_data("<ANTHROPIC_API_KEY>") { ENV.fetch("ANTHROPIC_API_KEY", nil) }

  # Record mode: :new_episodes records new requests, :none plays back only
  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: %i[method uri body]
  }
end

# Allow real API connections for integration tests
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: [
    "api.openai.com",
    "openrouter.ai",
    "api.anthropic.com",
    "localhost",
    "127.0.0.1"
  ]
)

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Order matters for integration tests
  config.order = :defined

  # Clean up test indexes after each test
  config.after(:each) do
    Dir.glob("*.leann*").each { |f| FileUtils.rm_rf(f) }
    Dir.glob("test_*.leann*").each { |f| FileUtils.rm_rf(f) }
    Dir.glob("spec/tmp/**/*").each { |f| FileUtils.rm_rf(f) }
  end

  # Reset configuration after each test
  config.after(:each) do
    Leann.instance_variable_set(:@configuration, nil)
  end

  # Silence library progress output during specs
  config.before(:suite) do
    Leann.configure { |c| c.verbose = false }
  end

  config.before(:each) do
    Leann.configuration.verbose = false
  end

  # Tag for integration tests that need real API
  config.define_derived_metadata(file_path: %r{/integration/}) do |metadata|
    metadata[:integration] = true
  end
end

# Helper to check if we have API keys
def has_openai_key?
  ENV.fetch("OPENAI_API_KEY", nil) && !ENV["OPENAI_API_KEY"].empty?
end

def has_ollama?
  OLLAMA_AVAILABLE
end

# Helper to create test documents
def sample_documents
  [
    "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity.",
    "Rails is a web application framework written in Ruby. It follows the MVC pattern.",
    "Sinatra is a DSL for quickly creating web applications in Ruby with minimal effort.",
    "RSpec is a testing framework for Ruby, designed for behavior-driven development.",
    "Bundler provides a consistent environment for Ruby projects by tracking and installing gems."
  ]
end

# Create temp directory for tests
FileUtils.mkdir_p("spec/tmp")

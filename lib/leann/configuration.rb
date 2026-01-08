# frozen_string_literal: true

module Leann
  # Global configuration for Leann
  #
  # @example With RubyLLM (recommended)
  #   # If RubyLLM is present, LEANN uses it automatically
  #   # Just configure RubyLLM as usual:
  #   RubyLLM.configure do |config|
  #     config.openai_api_key = ENV["OPENAI_API_KEY"]
  #   end
  #
  # @example Manual configuration
  #   Leann.configure do |config|
  #     config.embedding_provider = :openai
  #     config.openai_api_key = ENV["OPENAI_API_KEY"]
  #   end
  #
  class Configuration
    # Embedding provider (:ruby_llm, :openai, :ollama, :fastembed)
    # Defaults to :ruby_llm if RubyLLM gem is available, otherwise :openai
    # @return [Symbol]
    attr_accessor :embedding_provider

    # OpenAI API key (only needed if not using RubyLLM)
    # @return [String, nil]
    attr_accessor :openai_api_key

    # OpenAI base URL (for custom endpoints)
    # @return [String, nil]
    attr_accessor :openai_base_url

    # Ollama host URL
    # @return [String]
    attr_accessor :ollama_host

    # Default embedding model
    # @return [String]
    attr_accessor :default_embedding_model

    # Index storage directory
    # @return [String]
    attr_accessor :index_directory

    # HNSW M parameter (graph connectivity)
    # @return [Integer]
    attr_accessor :hnsw_m

    # HNSW ef_construction parameter
    # @return [Integer]
    attr_accessor :hnsw_ef_construction

    # Default chunk size for text splitting
    # @return [Integer]
    attr_accessor :chunk_size

    # Default chunk overlap
    # @return [Integer]
    attr_accessor :chunk_overlap

    def initialize
      # Default to RubyLLM if available, otherwise OpenAI
      @embedding_provider = ruby_llm_available? ? :ruby_llm : :openai

      @openai_api_key = ENV["OPENAI_API_KEY"]
      @openai_base_url = ENV["OPENAI_BASE_URL"]
      @ollama_host = ENV.fetch("OLLAMA_HOST", "http://localhost:11434")
      @default_embedding_model = nil  # Let provider choose default

      @index_directory = ".leann"
      @hnsw_m = 32
      @hnsw_ef_construction = 200

      @chunk_size = 512
      @chunk_overlap = 64
    end

    # Check if RubyLLM gem is available
    # @return [Boolean]
    def ruby_llm_available?
      defined?(::RubyLLM) || gem_available?("ruby_llm")
    end

    # Check if FastEmbed gem is available
    # @return [Boolean]
    def fastembed_available?
      defined?(::Fastembed) || gem_available?("fastembed")
    end

    # Validate configuration
    # @raise [ConfigurationError] if configuration is invalid
    def validate!
      case embedding_provider
      when :ruby_llm
        unless ruby_llm_available?
          raise ConfigurationError, "RubyLLM gem is required. Add 'ruby_llm' to your Gemfile."
        end
      when :openai
        raise ConfigurationError, "OpenAI API key is required" if openai_api_key.nil? || openai_api_key.empty?
      when :ollama
        # Ollama doesn't require API key, just needs to be running
      when :fastembed
        unless fastembed_available?
          raise ConfigurationError, "FastEmbed gem is required. Add 'fastembed' to your Gemfile."
        end
      else
        raise ConfigurationError, "Unknown embedding provider: #{embedding_provider}"
      end

      true
    end

    # Get embedding model for a provider
    # @return [String, nil]
    def embedding_model_for(provider)
      # Return custom model if explicitly set
      return @default_embedding_model if @custom_embedding_model

      # Provider-specific defaults
      case provider
      when :ruby_llm
        nil  # RubyLLM uses its own configured default
      when :openai
        "text-embedding-3-small"
      when :ollama
        "nomic-embed-text"
      when :fastembed
        "BAAI/bge-small-en-v1.5"
      else
        @default_embedding_model
      end
    end

    def default_embedding_model=(value)
      @default_embedding_model = value
      @custom_embedding_model = true
    end

    private

    def gem_available?(name)
      Gem::Specification.find_by_name(name)
      true
    rescue Gem::LoadError
      false
    end
  end
end

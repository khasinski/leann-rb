# frozen_string_literal: true

require_relative "base"

module Leann
  module Embedding
    # RubyLLM embedding provider
    #
    # Uses RubyLLM's unified embedding API which supports multiple providers
    # (OpenAI, Ollama, etc.) through a single interface.
    #
    # @example
    #   provider = Leann::Embedding::RubyLLM.new
    #   vectors = provider.compute(["Hello world", "Another text"])
    #
    class RubyLLM < Base
      # @param model [String, nil] Embedding model (uses RubyLLM default if nil)
      def initialize(model: nil)
        super

        return if defined?(::RubyLLM)

        raise ConfigurationError, "RubyLLM gem is required. Add 'ruby_llm' to your Gemfile."
      end

      # Compute embeddings for texts
      # @param texts [Array<String>] Texts to embed
      # @return [Array<Array<Float>>] Embedding vectors
      def compute(texts)
        texts = Array(texts)
        return [] if texts.empty?

        options = {}
        options[:model] = @model if @model

        result = ::RubyLLM.embed(texts, **options)
        result.vectors
      rescue ::RubyLLM::Error => e
        raise EmbeddingError, "RubyLLM embedding failed: #{e.message}"
      end

      # @return [Integer] Embedding dimensions (model-dependent)
      def dimensions
        # Get dimensions by computing a test embedding
        @dimensions ||= begin
          test = compute(["test"])
          test.first&.size || 1536
        end
      end

      # @return [String] Provider name
      def provider_name
        :ruby_llm
      end
    end
  end
end

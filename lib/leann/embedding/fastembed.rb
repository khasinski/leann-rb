# frozen_string_literal: true

require_relative "base"

module Leann
  module Embedding
    # FastEmbed provider for local embeddings
    #
    # Uses ONNX Runtime for fast, local embedding generation without
    # requiring an API key or external service.
    #
    # @example
    #   provider = Leann::Embedding::FastEmbed.new(model: "BAAI/bge-small-en-v1.5")
    #   embeddings = provider.compute(["Hello", "World"])
    #
    class FastEmbed < Base
      MAX_BATCH_SIZE = 64

      # Supported models with their dimensions
      MODELS = {
        "BAAI/bge-small-en-v1.5" => 384,
        "BAAI/bge-base-en-v1.5" => 768,
        "intfloat/multilingual-e5-small" => 384,
        "nomic-ai/nomic-embed-text-v1.5" => 768
      }.freeze

      DEFAULT_MODEL = "BAAI/bge-small-en-v1.5"

      # @param model [String] FastEmbed model name
      # @param cache_dir [String, nil] Model cache directory
      # @param threads [Integer, nil] Number of ONNX threads
      def initialize(model: nil, cache_dir: nil, threads: nil)
        model ||= DEFAULT_MODEL
        super(model: model)

        @cache_dir = cache_dir || ENV["FASTEMBED_CACHE_PATH"]
        @threads = threads
        @client = nil

        check_gem!
      end

      # Compute embeddings for texts
      #
      # @param texts [Array<String>]
      # @return [Array<Array<Float>>]
      def compute(texts)
        return [] if texts.empty?

        all_embeddings = []

        in_batches(texts, MAX_BATCH_SIZE) do |batch|
          batch_embeddings = compute_batch(batch)
          all_embeddings.concat(batch_embeddings)
          print "." # Progress indicator
        end

        puts " Done! (#{all_embeddings.size} embeddings)" unless texts.size < MAX_BATCH_SIZE

        # FastEmbed returns normalized vectors by default
        all_embeddings
      end

      # Get dimensions for the configured model
      # @return [Integer]
      def dimensions
        @dimensions ||= MODELS[model] || detect_dimensions
      end

      private

      def check_gem!
        unless defined?(::Fastembed)
          raise ConfigurationError, <<~MSG
            FastEmbed gem is required for local embeddings.

            Add to your Gemfile:
              gem 'fastembed'

            Or install directly:
              gem install fastembed
          MSG
        end
      end

      def client
        @client ||= begin
          options = { model_name: model }
          options[:cache_dir] = @cache_dir if @cache_dir
          options[:threads] = @threads if @threads

          ::Fastembed::TextEmbedding.new(**options)
        end
      end

      def compute_batch(texts)
        # FastEmbed returns a lazy enumerator, convert to array
        client.embed(texts, batch_size: texts.size).to_a
      rescue ::Fastembed::Error => e
        raise EmbeddingError.new(
          "FastEmbed error: #{e.message}",
          provider: :fastembed,
          original_error: e
        )
      rescue StandardError => e
        raise EmbeddingError.new(
          "FastEmbed error: #{e.message}",
          provider: :fastembed,
          original_error: e
        )
      end

      def detect_dimensions
        # Compute a single embedding to detect dimensions
        sample = client.embed(["test"], batch_size: 1).first
        sample.size
      end
    end
  end
end

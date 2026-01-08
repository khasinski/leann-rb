# frozen_string_literal: true

module Leann
  module Embedding
    # Base class for embedding providers
    #
    # Subclasses must implement:
    # - #compute(texts) -> Array<Array<Float>>
    #
    class Base
      # @return [String] Model name
      attr_reader :model

      # @return [Integer, nil] Embedding dimensions
      attr_reader :dimensions

      # @param model [String] Embedding model name
      def initialize(model:)
        @model = model
        @dimensions = nil
      end

      # Compute embeddings for a list of texts
      #
      # @param texts [Array<String>] Texts to embed
      # @return [Array<Array<Float>>] Embeddings (one per text)
      # @raise [NotImplementedError] if not overridden
      def compute(texts)
        raise NotImplementedError, "Subclasses must implement #compute"
      end

      # Compute embedding for a single text
      #
      # @param text [String]
      # @return [Array<Float>]
      def compute_one(text)
        compute([text]).first
      end

      protected

      # Normalize embedding to unit length (L2 normalization)
      # @param embedding [Array<Float>]
      # @return [Array<Float>]
      def normalize(embedding)
        norm = Math.sqrt(embedding.sum { |x| x * x })
        return embedding if norm.zero?

        embedding.map { |x| x / norm }
      end

      # Batch processing helper
      # @param items [Array]
      # @param batch_size [Integer]
      # @yield [Array] Each batch
      def in_batches(items, batch_size)
        items.each_slice(batch_size) do |batch|
          yield batch
        end
      end
    end
  end
end

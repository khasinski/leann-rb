# frozen_string_literal: true

module Leann
  module Backend
    # Base class for vector storage backends
    #
    # Subclasses must implement:
    # - #build(embeddings, ids, path) - build index from embeddings
    # - #search(query_embedding, limit:) - search for nearest neighbors
    # - .load(path) - load existing index
    #
    class Base
      # @return [Integer] Embedding dimensions
      attr_reader :dimensions

      # @param dimensions [Integer]
      def initialize(dimensions:)
        @dimensions = dimensions
      end

      # Build an index from embeddings
      #
      # @param embeddings [Array<Array<Float>>]
      # @param ids [Array<String>]
      # @param path [String] Index path
      # @raise [NotImplementedError]
      def build(embeddings, ids, path)
        raise NotImplementedError, "Subclasses must implement #build"
      end

      # Search for nearest neighbors
      #
      # @param query_embedding [Array<Float>]
      # @param limit [Integer]
      # @return [Array<Array(String, Float)>] Array of [id, score] pairs
      # @raise [NotImplementedError]
      def search(query_embedding, limit:)
        raise NotImplementedError, "Subclasses must implement #search"
      end

      # Load an existing index
      #
      # @param path [String]
      # @return [Base]
      # @raise [NotImplementedError]
      def self.load(path)
        raise NotImplementedError, "Subclasses must implement .load"
      end
    end
  end
end

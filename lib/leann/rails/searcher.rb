# frozen_string_literal: true

module Leann
  module Rails
    # Handles search operations on a database-stored index
    class Searcher
      # @return [Leann::Rails::Index]
      attr_reader :index

      # @param index [Leann::Rails::Index]
      def initialize(index)
        @index = index
        @embedding_provider = nil
      end

      # Search the index
      #
      # @param query [String] Search query
      # @param limit [Integer] Maximum results
      # @param threshold [Float, nil] Minimum score threshold
      # @param filters [Hash, nil] Metadata filters
      # @return [Leann::SearchResults]
      def search(query, limit: 5, threshold: nil, filters: nil)
        start_time = Time.now

        # Compute query embedding
        query_embedding = embedding_provider.compute([query]).first

        # Load all passages for embedding recomputation
        passages = load_all_passages

        # Search with on-the-fly embedding recomputation
        backend = ActiveRecordBackend.new(index)
        raw_results = backend.search(
          query_embedding,
          embedding_provider: embedding_provider,
          passages: passages,
          limit: limit * 2
        )

        # Build results
        results = raw_results.map do |id, score|
          passage = index.passages.find_by(external_id: id)
          next unless passage

          Leann::SearchResult.new(
            id: id,
            text: passage.text,
            score: score,
            metadata: passage.metadata_sym
          )
        end.compact

        # Apply threshold filter
        results = results.select { |r| r.score >= threshold } if threshold

        # Apply metadata filters
        results = apply_filters(results, filters) if filters

        # Limit and sort results
        results = results.sort.first(limit)

        duration = Time.now - start_time

        Leann::SearchResults.new(results, query: query, duration: duration)
      end

      private

      def embedding_provider
        @embedding_provider ||= load_embedding_provider
      end

      def load_embedding_provider
        case index.embedding_provider_sym
        when :ruby_llm
          require "leann/embedding/ruby_llm"
          Leann::Embedding::RubyLLM.new(model: index.embedding_model)
        when :openai
          require "leann/embedding/openai"
          Leann::Embedding::OpenAI.new(model: index.embedding_model)
        when :ollama
          require "leann/embedding/ollama"
          Leann::Embedding::Ollama.new(model: index.embedding_model)
        else
          raise Leann::ConfigurationError, "Unknown embedding provider: #{index.embedding_provider}"
        end
      end

      def load_all_passages
        index.passages.pluck(:external_id, :text).to_h
      end

      def apply_filters(results, filters)
        results.select do |result|
          filters.all? do |key, value|
            metadata_value = result.metadata[key.to_sym]

            case value
            when Range
              value.cover?(metadata_value)
            when Array
              value.include?(metadata_value)
            when Regexp
              value.match?(metadata_value.to_s)
            else
              metadata_value == value
            end
          end
        end
      end
    end
  end
end

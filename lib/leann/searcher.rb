# frozen_string_literal: true

require "json"

module Leann
  # Handles search operations on an index
  class Searcher
    # @return [Index]
    attr_reader :index

    # @param index [Index]
    def initialize(index)
      @index = index
      @backend = nil
      @embedding_provider = nil
      @offsets = nil
      @passages_cache = nil
    end

    # Search the index
    #
    # @param query [String] Search query
    # @param limit [Integer] Maximum results (default: 5)
    # @param threshold [Float, nil] Minimum score threshold (0.0-1.0)
    # @param filters [Hash, nil] Metadata filters
    # @return [SearchResults]
    #
    # @example Basic search
    #   results = searcher.search("machine learning")
    #
    # @example With options
    #   results = searcher.search("auth", limit: 10, threshold: 0.7)
    #
    # @example With metadata filters
    #   results = searcher.search("query", filters: { category: "docs" })
    def search(query, limit: 5, threshold: nil, filters: nil)
      start_time = Time.now

      # Compute query embedding
      query_embedding = embedding_provider.compute([query]).first

      # Load all passages for on-the-fly embedding computation
      passages = load_all_passages

      # Search with on-the-fly embedding recomputation
      raw_results = backend.search(
        query_embedding,
        embedding_provider: embedding_provider,
        passages: passages,
        limit: limit * 2
      )

      # Load passages and build results
      results = raw_results.map do |id, score|
        passage = load_passage(id)
        next unless passage

        SearchResult.new(
          id: id,
          text: passage[:text],
          score: score,
          metadata: passage[:metadata] || {}
        )
      end.compact

      # Apply threshold filter
      results = results.select { |r| r.score >= threshold } if threshold

      # Apply metadata filters
      results = apply_filters(results, filters) if filters

      # Limit and sort results
      results = results.sort.first(limit)

      duration = Time.now - start_time

      SearchResults.new(results, query: query, duration: duration)
    end

    private

    def backend
      @backend ||= load_backend
    end

    def load_backend
      require_relative "backend/leann_graph"
      Backend::LeannGraph.load(index.path)
    end

    def load_all_passages
      return @passages_cache if @passages_cache

      @passages_cache = {}
      passages_file = "#{index.path}#{Index::PASSAGES_SUFFIX}"
      return @passages_cache unless File.exist?(passages_file)

      File.foreach(passages_file) do |line|
        doc = JSON.parse(line, symbolize_names: true)
        @passages_cache[doc[:id]] = doc[:text]
      end

      @passages_cache
    end

    def embedding_provider
      @embedding_provider ||= load_embedding_provider
    end

    def load_embedding_provider
      require_relative "embedding/base"

      case index.embedding_provider
      when :ruby_llm
        require_relative "embedding/ruby_llm"
        Embedding::RubyLLM.new(model: index.embedding_model)
      when :openai
        require_relative "embedding/openai"
        Embedding::OpenAI.new(model: index.embedding_model)
      when :ollama
        require_relative "embedding/ollama"
        Embedding::Ollama.new(model: index.embedding_model)
      when :fastembed
        require_relative "embedding/fastembed"
        Embedding::FastEmbed.new(model: index.embedding_model)
      else
        raise ConfigurationError, "Unknown embedding provider: #{index.embedding_provider}"
      end
    end

    def offsets
      @offsets ||= load_offsets
    end

    def load_offsets
      offsets_file = "#{index.path}#{Index::OFFSETS_SUFFIX}"
      return {} unless File.exist?(offsets_file)

      JSON.parse(File.read(offsets_file))
    rescue JSON::ParserError
      {}
    end

    def load_passage(id)
      passages_file = "#{index.path}#{Index::PASSAGES_SUFFIX}"
      return nil unless File.exist?(passages_file)

      offset = offsets[id]

      if offset
        # Fast random access using offset
        File.open(passages_file, "r") do |f|
          f.seek(offset)
          line = f.gets
          return JSON.parse(line, symbolize_names: true) if line
        end
      else
        # Fallback to linear scan (slower but works without offsets)
        File.foreach(passages_file) do |line|
          doc = JSON.parse(line, symbolize_names: true)
          return doc if doc[:id] == id
        end
      end

      nil
    rescue JSON::ParserError
      nil
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

# frozen_string_literal: true

require_relative "leann/version"
require_relative "leann/configuration"
require_relative "leann/errors"
require_relative "leann/search_result"
require_relative "leann/embedding/base"
require_relative "leann/embedding/openai"
require_relative "leann/embedding/ollama"
require_relative "leann/backend/base"
require_relative "leann/backend/leann_graph"
require_relative "leann/index"
require_relative "leann/builder"
require_relative "leann/searcher"

# LEANN - Lightweight Embedding-Aware Neural Neighbor search
#
# A Ruby gem for building and searching vector indexes with minimal storage.
# Stores only the graph structure, achieving 85-96% storage savings by
# recomputing embeddings on-the-fly during search.
#
# @example Quick start - build an index
#   Leann.build("knowledge_base") do
#     add "LEANN saves 85-96% storage compared to traditional vector databases."
#     add "It uses graph-only storage with on-demand recomputation."
#   end
#
# @example Search
#   results = Leann.search("knowledge_base", "storage savings")
#   results.each { |r| puts "#{r.score}: #{r.text}" }
#
module Leann
  class << self
    # Global configuration
    # @return [Configuration]
    def configuration
      @configuration ||= Configuration.new
    end

    # Configure Leann globally
    #
    # @example
    #   Leann.configure do |config|
    #     config.embedding_provider = :openai
    #     config.openai_api_key = ENV["OPENAI_API_KEY"]
    #   end
    #
    # @yield [Configuration]
    def configure
      yield(configuration)
    end

    # Build a new index with a DSL block
    #
    # @param name [String] Index name (will be created in current directory or specified path)
    # @param options [Hash] Options for building
    # @option options [Symbol] :embedding (:openai) Embedding provider (:openai, :ollama, :ruby_llm)
    # @option options [String] :model Embedding model name
    # @option options [String] :path Custom path for index storage
    #
    # @example Simple usage
    #   Leann.build("my_index") do
    #     add "First document"
    #     add "Second document"
    #   end
    #
    # @example With metadata
    #   Leann.build("docs", embedding: :ollama) do
    #     add "Content here", source: "file.md", chapter: 1
    #     add_file "README.md"
    #     add_directory "docs/", pattern: "**/*.md"
    #   end
    #
    # @return [Index] The built index
    def build(name, **options, &block)
      builder = Builder.new(name, **options)
      builder.instance_eval(&block) if block_given?
      builder.save
    end

    # Search an existing index
    #
    # @param name [String] Index name or path
    # @param query [String] Search query
    # @param limit [Integer] Maximum results (default: 5)
    # @param threshold [Float] Minimum similarity score (0.0-1.0)
    # @param filters [Hash] Metadata filters
    #
    # @example Basic search
    #   results = Leann.search("my_index", "machine learning")
    #
    # @example With filters
    #   results = Leann.search("docs", "auth", limit: 10, filters: { chapter: 1..5 })
    #
    # @return [Array<SearchResult>] Search results
    def search(name, query, limit: 5, threshold: nil, filters: nil)
      index = Index.open(name)
      index.search(query, limit: limit, threshold: threshold, filters: filters)
    end

    # Open an existing index for advanced operations
    #
    # @param name [String] Index name or path
    # @return [Index]
    def open(name)
      Index.open(name)
    end

    # List all indexes in a directory
    #
    # @param path [String] Directory to scan (default: current directory)
    # @return [Array<String>] Index names
    def list(path: ".")
      Index.list(path)
    end

    # Check if an index exists
    #
    # @param name [String] Index name or path
    # @return [Boolean]
    def exists?(name)
      Index.exists?(name)
    end

    # Delete an index
    #
    # @param name [String] Index name or path
    # @return [Boolean] true if deleted
    def delete(name)
      Index.delete(name)
    end
  end
end

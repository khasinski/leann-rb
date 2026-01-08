# frozen_string_literal: true

require "json"
require "fileutils"

module Leann
  # Represents a Leann index on disk
  #
  # @example Open and search
  #   index = Leann::Index.open("my_index")
  #   results = index.search("query")
  #
  # @example Get info
  #   index = Leann::Index.open("my_index")
  #   puts index.document_count
  #   puts index.embedding_model
  #
  class Index
    # @return [String] Index name
    attr_reader :name

    # @return [String] Index path
    attr_reader :path

    # @return [Hash] Index metadata
    attr_reader :metadata

    INDEX_EXTENSION = ".leann"
    META_SUFFIX = ".meta.json"
    PASSAGES_SUFFIX = ".passages.jsonl"
    OFFSETS_SUFFIX = ".passages.offsets"
    VECTORS_SUFFIX = ".vectors"
    IDS_SUFFIX = ".ids"

    class << self
      # Open an existing index
      # @param name [String] Index name or path
      # @return [Index]
      # @raise [IndexNotFoundError] if index doesn't exist
      def open(name)
        path = resolve_path(name)
        raise IndexNotFoundError, name unless exists_at?(path)

        new(path)
      end

      # Check if an index exists
      # @param name [String] Index name or path
      # @return [Boolean]
      def exists?(name)
        path = resolve_path(name)
        exists_at?(path)
      end

      # List all indexes in a directory
      # @param directory [String]
      # @return [Array<String>]
      def list(directory = ".")
        pattern = File.join(directory, "**", "*#{META_SUFFIX}")
        Dir.glob(pattern).map do |meta_file|
          # Extract index name from path
          File.basename(meta_file, META_SUFFIX).sub(/#{INDEX_EXTENSION}$/, "")
        end.uniq.sort
      end

      # Delete an index
      # @param name [String] Index name or path
      # @return [Boolean]
      def delete(name)
        path = resolve_path(name)
        return false unless exists_at?(path)

        # Delete all index files
        files_to_delete = [
          "#{path}#{META_SUFFIX}",
          "#{path}#{PASSAGES_SUFFIX}",
          "#{path}#{OFFSETS_SUFFIX}",
          "#{path}#{VECTORS_SUFFIX}",
          "#{path}#{IDS_SUFFIX}",
          "#{path}.graph.bin",     # LEANN graph file
          "#{path}.graph.meta.json" # LEANN graph metadata
        ]

        files_to_delete.each do |file|
          FileUtils.rm_f(file)
        end

        true
      end

      private

      def resolve_path(name)
        # If it's already a full path with extension, use it
        return name if name.end_with?(INDEX_EXTENSION)

        # Check in current directory
        local_path = "#{name}#{INDEX_EXTENSION}"
        return local_path if exists_at?(local_path)

        # Check in configured index directory
        config_dir = Leann.configuration.index_directory
        if config_dir && Dir.exist?(config_dir)
          configured_path = File.join(config_dir, "#{name}#{INDEX_EXTENSION}")
          return configured_path if exists_at?(configured_path)
        end

        # Return local path as default
        local_path
      end

      def exists_at?(path)
        meta_file = "#{path}#{META_SUFFIX}"
        File.exist?(meta_file)
      end
    end

    # @param path [String] Full path to index
    def initialize(path)
      @path = path
      @name = File.basename(path, INDEX_EXTENSION)
      @metadata = load_metadata
      @searcher = nil
    end

    # Search the index
    # @param query [String] Search query
    # @param limit [Integer] Maximum results
    # @param threshold [Float, nil] Minimum score threshold
    # @param filters [Hash, nil] Metadata filters
    # @return [SearchResults]
    def search(query, limit: 5, threshold: nil, filters: nil)
      searcher.search(query, limit: limit, threshold: threshold, filters: filters)
    end

    # Get number of documents in the index
    # @return [Integer]
    def document_count
      metadata["document_count"] || count_documents
    end

    # Get embedding model used
    # @return [String]
    def embedding_model
      metadata["embedding_model"]
    end

    # Get embedding provider
    # @return [Symbol]
    def embedding_provider
      (metadata["embedding_provider"] || "openai").to_sym
    end

    # Get embedding dimensions
    # @return [Integer]
    def dimensions
      metadata["dimensions"]
    end

    # Get creation timestamp
    # @return [Time, nil]
    def created_at
      return nil unless metadata["created_at"]

      Time.parse(metadata["created_at"])
    end

    # Get backend type
    # @return [Symbol]
    def backend
      (metadata["backend"] || "leann").to_sym
    end

    # Index info as string
    # @return [String]
    def to_s
      lines = [
        "Index: #{name}",
        "  Documents: #{document_count}",
        "  Embedding: #{embedding_provider}/#{embedding_model}",
        "  Dimensions: #{dimensions}",
        "  Backend: #{backend}",
        "  Created: #{created_at&.strftime("%Y-%m-%d %H:%M:%S") || "unknown"}"
      ]
      lines.join("\n")
    end

    # Detailed inspection
    # @return [String]
    def inspect
      "#<Leann::Index name=#{name.inspect} documents=#{document_count} model=#{embedding_model.inspect}>"
    end

    # Get all passages (lazy loaded)
    # @return [Enumerator]
    def each_passage
      return enum_for(:each_passage) unless block_given?

      passages_file = "#{path}#{PASSAGES_SUFFIX}"
      return unless File.exist?(passages_file)

      File.foreach(passages_file) do |line|
        yield JSON.parse(line.strip, symbolize_names: true)
      end
    end

    # Get passage by ID
    # @param id [String]
    # @return [Hash, nil]
    def get_passage(id)
      each_passage.find { |p| p[:id] == id }
    end

    private

    def load_metadata
      meta_file = "#{path}#{META_SUFFIX}"
      JSON.parse(File.read(meta_file))
    rescue JSON::ParserError => e
      raise CorruptedIndexError.new(name, "Invalid metadata JSON: #{e.message}")
    rescue Errno::ENOENT
      raise IndexNotFoundError, name
    end

    def count_documents
      passages_file = "#{path}#{PASSAGES_SUFFIX}"
      return 0 unless File.exist?(passages_file)

      File.foreach(passages_file).count
    end

    def searcher
      @searcher ||= Searcher.new(self)
    end
  end
end

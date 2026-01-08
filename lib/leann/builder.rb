# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "time"

module Leann
  # Builds a new Leann index
  #
  # @example DSL style
  #   Leann.build("my_index") do
  #     add "First document"
  #     add "Second document", source: "manual"
  #     add_file "README.md"
  #   end
  #
  # @example Programmatic style
  #   builder = Leann::Builder.new("my_index")
  #   builder.add("First document")
  #   builder.add("Second document")
  #   builder.save
  #
  class Builder
    # @return [String] Index name
    attr_reader :name

    # @return [String] Index path
    attr_reader :path

    # @return [Array<Hash>] Documents to be indexed
    attr_reader :documents

    # @param name [String] Index name
    # @param embedding [Symbol] Embedding provider (:ruby_llm, :openai, :ollama, :fastembed)
    # @param model [String, nil] Embedding model name
    # @param path [String, nil] Custom path for index
    # @param force [Boolean] Overwrite existing index
    def initialize(name, embedding: nil, model: nil, path: nil, force: false, **_options)
      @name = name
      @path = resolve_path(name, path)
      @embedding_provider = embedding || Leann.configuration.embedding_provider
      @embedding_model = model || Leann.configuration.embedding_model_for(@embedding_provider)
      @force = force
      @documents = []

      check_existing_index unless force
    end

    # Add a text document
    #
    # @param text [String] Document text
    # @param metadata [Hash] Additional metadata (passed as keyword arguments)
    # @return [self]
    #
    # @example
    #   builder.add("Hello world")
    #   builder.add("Document with metadata", source: "file.txt", chapter: 1)
    def add(text, **metadata)
      raise ArgumentError, "Text cannot be nil" if text.nil?
      raise ArgumentError, "Text cannot be empty" if text.to_s.strip.empty?

      doc = {
        id: metadata.delete(:id) || generate_id,
        text: text.to_s.strip,
        metadata: metadata
      }

      @documents << doc
      self
    end

    # Add document (alias for add)
    alias << add

    # Add content from a file
    #
    # @param file_path [String] Path to file
    # @param metadata [Hash] Additional metadata
    # @return [self]
    #
    # @example
    #   builder.add_file("README.md")
    #   builder.add_file("docs/guide.txt", category: "documentation")
    def add_file(file_path, **metadata)
      raise ArgumentError, "File not found: #{file_path}" unless File.exist?(file_path)

      content = File.read(file_path)
      file_metadata = {
        source: file_path,
        filename: File.basename(file_path),
        extension: File.extname(file_path)
      }.merge(metadata)

      add(content, **file_metadata)
    end

    # Add all files from a directory
    #
    # @param directory [String] Directory path
    # @param pattern [String] Glob pattern (default: "**/*")
    # @param extensions [Array<String>, nil] Filter by extensions (e.g., [".md", ".txt"])
    # @param metadata [Hash] Additional metadata for all files
    # @return [self]
    #
    # @example
    #   builder.add_directory("docs/")
    #   builder.add_directory("src/", extensions: [".rb", ".py"])
    def add_directory(directory, pattern: "**/*", extensions: nil, **metadata)
      raise ArgumentError, "Directory not found: #{directory}" unless Dir.exist?(directory)

      full_pattern = File.join(directory, pattern)
      Dir.glob(full_pattern).each do |file_path|
        next unless File.file?(file_path)
        next if extensions && !extensions.include?(File.extname(file_path))

        add_file(file_path, **metadata)
      end

      self
    end

    # Add multiple documents at once
    #
    # @param docs [Array<String>, Array<Hash>] Documents to add
    # @return [self]
    #
    # @example
    #   builder.add_all(["Doc 1", "Doc 2", "Doc 3"])
    #   builder.add_all([
    #     { text: "Doc 1", source: "a" },
    #     { text: "Doc 2", source: "b" }
    #   ])
    def add_all(docs)
      docs.each do |doc|
        case doc
        when String
          add(doc)
        when Hash
          text = doc.delete(:text) || doc.delete("text")
          add(text, **doc.transform_keys(&:to_sym))
        else
          raise ArgumentError, "Invalid document type: #{doc.class}"
        end
      end

      self
    end

    # Get number of documents added
    # @return [Integer]
    def count
      @documents.size
    end
    alias size count

    # Check if any documents have been added
    # @return [Boolean]
    def empty?
      @documents.empty?
    end

    # Build and save the index
    # @return [Index] The built index
    def save
      raise EmptyIndexError if empty?

      puts "Building index '#{name}' with #{count} documents..."

      # Create directory if needed
      FileUtils.mkdir_p(File.dirname(path))

      # Delete existing if force mode
      Index.delete(path) if @force && Index.exists?(path)

      # Compute embeddings
      embeddings = compute_embeddings

      # Save passages
      save_passages

      # Build and save graph
      save_graph(embeddings)

      # Save metadata
      save_metadata(embeddings)

      puts "Index '#{name}' created successfully!"

      Index.open(path)
    end
    alias build save

    private

    def resolve_path(name, custom_path)
      if custom_path
        custom_path.end_with?(Index::INDEX_EXTENSION) ? custom_path : "#{custom_path}#{Index::INDEX_EXTENSION}"
      else
        "#{name}#{Index::INDEX_EXTENSION}"
      end
    end

    def check_existing_index
      raise IndexExistsError, name if Index.exists?(path)
    end

    def generate_id
      SecureRandom.uuid
    end

    def compute_embeddings
      texts = @documents.map { |d| d[:text] }
      embedding_provider.compute(texts)
    end

    def embedding_provider
      @_embedding_provider ||= load_embedding_provider
    end

    def load_embedding_provider
      require_relative "embedding/base"

      case @embedding_provider
      when :ruby_llm
        require_relative "embedding/ruby_llm"
        Embedding::RubyLLM.new(model: @embedding_model)
      when :openai
        require_relative "embedding/openai"
        Embedding::OpenAI.new(model: @embedding_model)
      when :ollama
        require_relative "embedding/ollama"
        Embedding::Ollama.new(model: @embedding_model)
      when :fastembed
        require_relative "embedding/fastembed"
        Embedding::FastEmbed.new(model: @embedding_model)
      else
        raise ConfigurationError, "Unknown embedding provider: #{@embedding_provider}"
      end
    end

    def save_passages
      passages_file = "#{path}#{Index::PASSAGES_SUFFIX}"
      offsets_file = "#{path}#{Index::OFFSETS_SUFFIX}"

      offsets = {}

      File.open(passages_file, "w") do |f|
        @documents.each do |doc|
          offsets[doc[:id]] = f.pos
          f.puts(JSON.generate(doc))
        end
      end

      File.write(offsets_file, JSON.generate(offsets))
    end

    def save_graph(embeddings)
      ids = @documents.map { |d| d[:id] }

      require_relative "backend/leann_graph"

      graph = Backend::LeannGraph.new(
        dimensions: embeddings.first.size,
        m: Leann.configuration.hnsw_m,
        ef_construction: Leann.configuration.hnsw_ef_construction
      )

      graph.build(ids, embeddings)
      graph.save(path)

      report_storage_savings(embeddings)
    end

    def report_storage_savings(embeddings)
      embedding_size = embeddings.first.size * 4  # float32
      total_embedding_bytes = embeddings.length * embedding_size

      graph_file = "#{path}.graph.bin"
      actual_size = File.exist?(graph_file) ? File.size(graph_file) : 0

      savings = ((total_embedding_bytes - actual_size).to_f / total_embedding_bytes * 100).round(1)
      puts "Storage savings: #{savings}% (#{format_bytes(total_embedding_bytes)} → #{format_bytes(actual_size)})"
    end

    def format_bytes(bytes)
      if bytes < 1024
        "#{bytes} B"
      elsif bytes < 1024 * 1024
        "#{(bytes / 1024.0).round(1)} KB"
      else
        "#{(bytes / (1024.0 * 1024)).round(2)} MB"
      end
    end

    def save_metadata(embeddings)
      meta_file = "#{path}#{Index::META_SUFFIX}"

      metadata = {
        version: "1.0",
        name: name,
        backend: "leann",
        embedding_provider: @embedding_provider.to_s,
        embedding_model: @embedding_model,
        dimensions: embeddings.first&.size || 0,
        document_count: @documents.size,
        created_at: Time.now.utc.iso8601,
        config: {
          hnsw_m: Leann.configuration.hnsw_m,
          hnsw_ef_construction: Leann.configuration.hnsw_ef_construction
        }
      }

      File.write(meta_file, JSON.pretty_generate(metadata))
    end
  end
end

# frozen_string_literal: true

require "securerandom"

module Leann
  module Rails
    # Builds a new LEANN index stored in the database
    #
    # @example DSL style
    #   Leann::Rails.build("products") do
    #     add "Red running shoes", category: "shoes"
    #     add "Blue denim jeans", category: "pants"
    #   end
    #
    # @example Programmatic style
    #   builder = Leann::Rails::Builder.new("products")
    #   builder.add("Red running shoes", category: "shoes")
    #   builder.save
    #
    class Builder
      # @return [String] Index name
      attr_reader :name

      # @return [Array<Hash>] Documents to be indexed
      attr_reader :documents

      # @param name [String] Index name (must be unique)
      # @param embedding [Symbol] Embedding provider (:ruby_llm, :openai, :ollama, :fastembed)
      # @param model [String, nil] Embedding model name
      # @param force [Boolean] Overwrite existing index
      def initialize(name, embedding: nil, model: nil, force: false)
        @name = name
        @embedding_provider = embedding || Leann.configuration.embedding_provider
        @embedding_model = model || Leann.configuration.embedding_model_for(@embedding_provider)
        @force = force
        @documents = []

        check_existing_index unless force
      end

      # Add a text document
      #
      # @param text [String] Document text
      # @param metadata [Hash] Additional metadata
      # @return [self]
      def add(text, **metadata)
        raise ArgumentError, "Text cannot be nil" if text.nil?
        raise ArgumentError, "Text cannot be empty" if text.to_s.strip.empty?

        doc = {
          id: metadata.delete(:id) || SecureRandom.uuid,
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
      # @param pattern [String] Glob pattern
      # @param extensions [Array<String>, nil] Filter by extensions
      # @param metadata [Hash] Additional metadata for all files
      # @return [self]
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

      # Build and save the index to the database
      # @return [Leann::Rails::Index] The built index record
      def save
        raise Leann::EmptyIndexError if empty?

        puts "Building index '#{name}' with #{count} documents..."

        # Delete existing if force mode
        Index.find_by(name: name)&.destroy if @force

        # Compute embeddings
        embeddings = compute_embeddings

        # Create index record
        index = Index.create!(
          name: name,
          embedding_provider: @embedding_provider.to_s,
          embedding_model: @embedding_model,
          dimensions: embeddings.first&.size || 0,
          config: {
            hnsw_m: Leann.configuration.hnsw_m,
            hnsw_ef_construction: Leann.configuration.hnsw_ef_construction
          }
        )

        # Build and store graph
        backend = ActiveRecordBackend.new(index)
        backend.build(@documents, embeddings)

        puts "Index '#{name}' created successfully!"

        index
      end
      alias build save

      private

      def check_existing_index
        raise Leann::IndexExistsError, name if Index.exists?(name: name)
      end

      def compute_embeddings
        texts = @documents.map { |d| d[:text] }
        embedding_provider.compute(texts)
      end

      def embedding_provider
        @_embedding_provider ||= load_embedding_provider
      end

      def load_embedding_provider
        case @embedding_provider
        when :ruby_llm
          require "leann/embedding/ruby_llm"
          Leann::Embedding::RubyLLM.new(model: @embedding_model)
        when :openai
          require "leann/embedding/openai"
          Leann::Embedding::OpenAI.new(model: @embedding_model)
        when :ollama
          require "leann/embedding/ollama"
          Leann::Embedding::Ollama.new(model: @embedding_model)
        when :fastembed
          require "leann/embedding/fastembed"
          Leann::Embedding::FastEmbed.new(model: @embedding_model)
        else
          raise Leann::ConfigurationError, "Unknown embedding provider: #{@embedding_provider}"
        end
      end
    end
  end
end

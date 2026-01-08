# frozen_string_literal: true

require_relative "../leann"

module Leann
  module Rails
    autoload :Index, "leann/rails/active_record/index"
    autoload :Passage, "leann/rails/active_record/passage"
    autoload :ActiveRecordBackend, "leann/rails/storage/active_record_backend"
    autoload :Builder, "leann/rails/builder"
    autoload :Searcher, "leann/rails/searcher"

    class << self
      # Build a new index stored in the database
      #
      # @param name [String] Index name (unique identifier)
      # @param options [Hash] Options for building
      # @option options [Symbol] :embedding (:openai) Embedding provider
      # @option options [String] :model Embedding model name
      #
      # @example
      #   Leann::Rails.build("products") do
      #     add "Red running shoes for athletes", category: "shoes"
      #     add "Blue denim jeans, slim fit", category: "pants"
      #   end
      #
      # @return [Leann::Rails::Index] The built index record
      def build(name, **options, &block)
        builder = Builder.new(name, **options)
        builder.instance_eval(&block) if block_given?
        builder.save
      end

      # Search an existing database index
      #
      # @param name [String] Index name
      # @param query [String] Search query
      # @param limit [Integer] Maximum results
      # @param threshold [Float] Minimum similarity score
      # @param filters [Hash] Metadata filters
      #
      # @example
      #   results = Leann::Rails.search("products", "comfortable shoes")
      #
      # @return [Leann::SearchResults]
      def search(name, query, limit: 5, threshold: nil, filters: nil)
        index = Index.find_by!(name: name)
        searcher = Searcher.new(index)
        searcher.search(query, limit: limit, threshold: threshold, filters: filters)
      end

      # Open an existing index
      #
      # @param name [String] Index name
      # @return [Leann::Rails::Index]
      def open(name)
        Index.find_by!(name: name)
      end

      # Check if an index exists
      #
      # @param name [String] Index name
      # @return [Boolean]
      def exists?(name)
        Index.exists?(name: name)
      end

      # Delete an index and all its passages
      #
      # @param name [String] Index name
      # @return [Boolean]
      def delete(name)
        index = Index.find_by(name: name)
        return false unless index

        index.destroy
        true
      end

      # List all indexes
      #
      # @return [Array<String>]
      def list
        Index.pluck(:name).sort
      end
    end
  end
end

require "leann/rails/railtie" if defined?(::Rails::Railtie)

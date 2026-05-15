# frozen_string_literal: true

module Leann
  module Rails
    # ActiveRecord model for storing LEANN indexes
    #
    # @example
    #   index = Leann::Rails::Index.find_by(name: "products")
    #   index.search("running shoes")
    #
    class Index < ::ActiveRecord::Base
      self.table_name = "leann_indexes"

      has_many :passages,
               class_name: "Leann::Rails::Passage",
               foreign_key: :leann_index_id,
               dependent: :delete_all

      validates :name, presence: true, uniqueness: true
      validates :embedding_provider, presence: true
      validates :dimensions, presence: true, numericality: { greater_than: 0 }

      serialize :config, coder: JSON

      # Search this index
      #
      # @param query [String] Search query
      # @param limit [Integer] Maximum results
      # @param threshold [Float] Minimum similarity score
      # @param filters [Hash] Metadata filters
      # @return [Leann::SearchResults]
      def search(query, limit: 5, threshold: nil, filters: nil)
        searcher = Searcher.new(self)
        searcher.search(query, limit: limit, threshold: threshold, filters: filters)
      end

      # Get number of documents
      # @return [Integer]
      def document_count
        passages.count
      end

      # Get embedding provider as symbol
      # @return [Symbol]
      def embedding_provider_sym
        embedding_provider.to_sym
      end

      # Index info as string
      # @return [String]
      def to_s
        lines = [
          "Index: #{name}",
          "  Documents: #{document_count}",
          "  Embedding: #{embedding_provider}/#{embedding_model}",
          "  Dimensions: #{dimensions}",
          "  Backend: active_record",
          "  Created: #{created_at&.strftime("%Y-%m-%d %H:%M:%S") || "unknown"}"
        ]
        lines.join("\n")
      end

      # Detailed inspection
      # @return [String]
      def inspect
        "#<Leann::Rails::Index id=#{id} name=#{name.inspect} documents=#{document_count}>"
      end
    end
  end
end

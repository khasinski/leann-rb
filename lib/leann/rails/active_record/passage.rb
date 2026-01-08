# frozen_string_literal: true

module Leann
  module Rails
    # ActiveRecord model for storing passages/documents within an index
    #
    # @example
    #   passage = Leann::Rails::Passage.find(123)
    #   passage.text      # => "Document content..."
    #   passage.metadata  # => { category: "docs" }
    #
    class Passage < ::ActiveRecord::Base
      self.table_name = "leann_passages"

      belongs_to :index,
                 class_name: "Leann::Rails::Index",
                 foreign_key: :leann_index_id

      validates :external_id, presence: true
      validates :text, presence: true
      validates :leann_index_id, presence: true

      serialize :metadata, coder: JSON
      serialize :neighbors, coder: JSON

      # Get metadata with symbolized keys
      # @return [Hash]
      def metadata_sym
        (metadata || {}).transform_keys(&:to_sym)
      end

      # Get neighbor IDs
      # @return [Array<String>]
      def neighbor_ids
        neighbors || []
      end

      # Convert to hash for search results
      # @return [Hash]
      def to_h
        {
          id: external_id,
          text: text,
          metadata: metadata_sym
        }
      end

      # Detailed inspection
      # @return [String]
      def inspect
        text_preview = text.length > 50 ? "#{text[0..47]}..." : text
        "#<Leann::Rails::Passage id=#{id} external_id=#{external_id.inspect} text=#{text_preview.inspect}>"
      end
    end
  end
end

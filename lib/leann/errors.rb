# frozen_string_literal: true

module Leann
  # Base error class for all Leann errors
  class Error < StandardError; end

  # Raised when configuration is invalid
  class ConfigurationError < Error; end

  # Raised when an index is not found
  class IndexNotFoundError < Error
    attr_reader :index_name

    def initialize(index_name)
      @index_name = index_name
      super("Index not found: #{index_name}")
    end
  end

  # Raised when an index already exists
  class IndexExistsError < Error
    attr_reader :index_name

    def initialize(index_name)
      @index_name = index_name
      super("Index already exists: #{index_name}. Use force: true to overwrite.")
    end
  end

  # Raised when embedding computation fails
  class EmbeddingError < Error
    attr_reader :provider, :original_error

    def initialize(message, provider: nil, original_error: nil)
      @provider = provider
      @original_error = original_error
      super(message)
    end
  end

  # Raised when LLM request fails
  class LLMError < Error
    attr_reader :provider, :original_error

    def initialize(message, provider: nil, original_error: nil)
      @provider = provider
      @original_error = original_error
      super(message)
    end
  end

  # Raised when index is corrupted or invalid
  class CorruptedIndexError < Error
    attr_reader :index_name, :reason

    def initialize(index_name, reason = nil)
      @index_name = index_name
      @reason = reason
      message = "Corrupted index: #{index_name}"
      message += " (#{reason})" if reason
      super(message)
    end
  end

  # Raised when no documents are provided to builder
  class EmptyIndexError < Error
    def initialize
      super("Cannot build an empty index. Add at least one document.")
    end
  end
end

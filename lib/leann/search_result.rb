# frozen_string_literal: true

module Leann
  # Represents a single search result
  #
  # @example
  #   results = Leann.search("my_index", "query")
  #   results.each do |result|
  #     puts result.text
  #     puts result.score
  #     puts result.metadata[:source]
  #   end
  #
  class SearchResult
    # @return [String] Document ID
    attr_reader :id

    # @return [String] Document text
    attr_reader :text

    # @return [Float] Similarity score (higher is better)
    attr_reader :score

    # @return [Hash] Document metadata
    attr_reader :metadata

    # @param id [String]
    # @param text [String]
    # @param score [Float]
    # @param metadata [Hash]
    def initialize(id:, text:, score:, metadata: {})
      @id = id
      @text = text
      @score = score.to_f
      @metadata = metadata.transform_keys(&:to_sym)
    end

    # Truncate text to a maximum length
    # @param max_length [Integer]
    # @param omission [String]
    # @return [String]
    def truncated_text(max_length = 100, omission: "...")
      return text if text.length <= max_length

      text[0, max_length - omission.length] + omission
    end

    # Human-readable string representation
    # @return [String]
    def to_s
      "[#{format("%.3f", score)}] #{truncated_text(80)}"
    end

    # Detailed inspection
    # @return [String]
    def inspect
      "#<Leann::SearchResult id=#{id.inspect} score=#{format("%.4f", score)} text=#{truncated_text(50).inspect}>"
    end

    # Convert to hash
    # @return [Hash]
    def to_h
      {
        id: id,
        text: text,
        score: score,
        metadata: metadata
      }
    end

    # Compare by score (for sorting)
    # @param other [SearchResult]
    # @return [Integer]
    def <=>(other)
      other.score <=> score # Descending order
    end

    # Check equality
    # @param other [SearchResult]
    # @return [Boolean]
    def ==(other)
      return false unless other.is_a?(SearchResult)

      id == other.id && text == other.text && score == other.score
    end
    alias eql? ==

    # Hash code for use as hash key
    # @return [Integer]
    def hash
      [id, text, score].hash
    end
  end

  # Collection of search results with utility methods
  class SearchResults
    include Enumerable

    # @return [Array<SearchResult>]
    attr_reader :results

    # @return [String] Original query
    attr_reader :query

    # @return [Float] Search duration in seconds
    attr_reader :duration

    # @param results [Array<SearchResult>]
    # @param query [String]
    # @param duration [Float]
    def initialize(results, query: nil, duration: nil)
      @results = results
      @query = query
      @duration = duration
    end

    # Iterate over results
    def each(&)
      results.each(&)
    end

    # Number of results
    # @return [Integer]
    def size
      results.size
    end
    alias length size
    alias count size

    # Check if empty
    # @return [Boolean]
    def empty?
      results.empty?
    end

    # Get first result
    # @return [SearchResult, nil]
    def first
      results.first
    end

    # Get top n results
    # @param n [Integer]
    # @return [Array<SearchResult>]
    def top(n)
      results.first(n)
    end

    # Get result by index
    # @param index [Integer]
    # @return [SearchResult, nil]
    def [](index)
      results[index]
    end

    # Filter results by minimum score
    # @param min_score [Float]
    # @return [SearchResults]
    def above(min_score)
      filtered = results.select { |r| r.score >= min_score }
      SearchResults.new(filtered, query: query, duration: duration)
    end

    # Get all texts
    # @return [Array<String>]
    def texts
      results.map(&:text)
    end

    # Join all texts
    # @param separator [String]
    # @return [String]
    def combined_text(separator: "\n\n")
      texts.join(separator)
    end

    # Pretty print results
    # @return [String]
    def to_s
      lines = ["Search results for: #{query.inspect}"]
      lines << "Found #{size} results in #{format("%.3f", duration || 0)}s"
      lines << ("-" * 60)
      results.each_with_index do |r, i|
        lines << "#{i + 1}. #{r}"
      end
      lines.join("\n")
    end

    # Convert to array of hashes
    # @return [Array<Hash>]
    def to_a
      results.map(&:to_h)
    end
  end
end

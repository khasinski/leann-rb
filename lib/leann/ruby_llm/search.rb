# frozen_string_literal: true

require_relative "../../leann"

# Only require ruby_llm if not already defined (allows mocking in tests)
unless defined?(RubyLLM::Tool)
  begin
    require "ruby_llm"
  rescue LoadError
    raise LoadError, "RubyLLM is required for Leann::RubyLLM::Search. Add 'ruby_llm' to your Gemfile."
  end
end

module Leann
  module RubyLLM
    # A RubyLLM tool for searching LEANN indexes
    #
    # @example Basic usage
    #   chat = ::RubyLLM.chat(model: "gpt-4o")
    #     .with_tool(Leann::RubyLLM::Search.new("my_index"))
    #
    #   chat.ask("What does LEANN do?")
    #   # => LLM searches the index and generates an answer
    #
    # @example Multiple indexes
    #   docs_search = Leann::RubyLLM::Search.new("docs", name: "search_docs")
    #   code_search = Leann::RubyLLM::Search.new("codebase", name: "search_code")
    #
    #   chat = ::RubyLLM.chat(model: "gpt-4o")
    #     .with_tools(docs_search, code_search)
    #
    class Search < ::RubyLLM::Tool
      # @param index_name [String] Name of the LEANN index to search
      # @param name [String] Tool name (defaults to "leann_search")
      # @param limit [Integer] Default number of results (default: 5)
      def initialize(index_name, name: "leann_search", limit: 5)
        @index_name = index_name
        @default_limit = limit
        @tool_name = name
        super()
      end

      def name
        @tool_name
      end

      def description
        "Searches the '#{@index_name}' knowledge base for relevant documents. " \
          "Use this to find information before answering questions."
      end

      def params
        ::RubyLLM::Schema.new do
          string :query,
                 description: "The search query to find relevant documents",
                 required: true
          integer :limit,
                  description: "Maximum number of results to return (default: #{@default_limit})",
                  required: false
        end
      end

      def execute(query:, limit: nil)
        limit ||= @default_limit
        results = Leann.search(@index_name, query, limit: limit)

        if results.empty?
          { found: false, message: "No relevant documents found for: #{query}" }
        else
          {
            found: true,
            count: results.size,
            documents: results.map do |r|
              {
                text: r.text,
                score: r.score.round(3),
                metadata: r.metadata
              }
            end
          }
        end
      rescue Leann::IndexNotFoundError
        { error: "Index '#{@index_name}' not found" }
      rescue StandardError => e
        { error: e.message }
      end
    end
  end
end

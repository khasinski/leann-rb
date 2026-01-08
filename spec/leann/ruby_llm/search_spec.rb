# frozen_string_literal: true

# Mock RubyLLM classes for testing without the actual gem
module RubyLLM
  class Tool
    def initialize; end
  end

  class Schema
    def initialize(&block)
      instance_eval(&block) if block_given?
    end

    def string(name, **options); end
    def integer(name, **options); end
  end
end

require_relative "../../../lib/leann/ruby_llm/search"

RSpec.describe Leann::RubyLLM::Search do
  let(:index_name) { "test_ruby_llm_#{Time.now.to_i}" }

  # Mock embedding provider for unit tests
  let(:mock_provider) do
    double("EmbeddingProvider").tap do |provider|
      allow(provider).to receive(:compute) do |texts|
        texts.map { Array.new(384) { rand(-1.0..1.0) } }
      end
    end
  end

  before do
    Leann.configure do |config|
      config.openai_api_key = "test-key"
    end
  end

  after do
    Dir.glob("#{index_name}*").each { |f| FileUtils.rm_rf(f) }
  end

  describe "#initialize" do
    it "creates a tool with default name" do
      tool = described_class.new(index_name)
      expect(tool.name).to eq("leann_search")
    end

    it "allows custom name" do
      tool = described_class.new(index_name, name: "search_docs")
      expect(tool.name).to eq("search_docs")
    end
  end

  describe "#description" do
    it "includes index name" do
      tool = described_class.new("my_index")
      expect(tool.description).to include("my_index")
    end
  end

  describe "#execute" do
    subject(:tool) { described_class.new(index_name) }

    context "with existing index" do
      before do
        builder = Leann::Builder.new(index_name)
        allow(builder).to receive(:embedding_provider).and_return(mock_provider)
        builder.add("Ruby is a dynamic programming language.")
        builder.add("Python is known for its readability.")
        builder.save
      end

      it "returns search results" do
        # Mock the search to avoid needing real embeddings
        allow(Leann).to receive(:search).and_return([
          Leann::SearchResult.new(
            id: "1",
            text: "Ruby is a dynamic programming language.",
            score: 0.95,
            metadata: {}
          )
        ])

        result = tool.execute(query: "dynamic language")

        expect(result[:found]).to be true
        expect(result[:count]).to eq(1)
        expect(result[:documents].first[:text]).to include("Ruby")
      end

      it "returns not found when no results" do
        allow(Leann).to receive(:search).and_return([])

        result = tool.execute(query: "nonexistent topic")

        expect(result[:found]).to be false
        expect(result[:message]).to include("No relevant documents")
      end
    end

    context "with missing index" do
      it "returns error" do
        result = tool.execute(query: "anything")

        expect(result[:error]).to include("not found")
      end
    end
  end
end

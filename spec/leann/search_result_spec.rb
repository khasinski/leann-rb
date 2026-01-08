# frozen_string_literal: true

RSpec.describe Leann::SearchResult do
  subject(:result) do
    described_class.new(
      id: "doc-123",
      text: "Ruby is a dynamic programming language.",
      score: 0.95,
      metadata: { source: "readme.md", chapter: 1 }
    )
  end

  describe "#initialize" do
    it "stores id" do
      expect(result.id).to eq("doc-123")
    end

    it "stores text" do
      expect(result.text).to eq("Ruby is a dynamic programming language.")
    end

    it "stores score as float" do
      expect(result.score).to eq(0.95)
      expect(result.score).to be_a(Float)
    end

    it "symbolizes metadata keys" do
      expect(result.metadata[:source]).to eq("readme.md")
      expect(result.metadata[:chapter]).to eq(1)
    end
  end

  describe "#truncated_text" do
    let(:long_result) do
      described_class.new(
        id: "long",
        text: "A" * 200,
        score: 0.5
      )
    end

    it "returns full text if under limit" do
      expect(result.truncated_text(100)).to eq(result.text)
    end

    it "truncates long text" do
      truncated = long_result.truncated_text(50)
      expect(truncated.length).to eq(50)
      expect(truncated).to end_with("...")
    end

    it "uses custom omission" do
      truncated = long_result.truncated_text(50, omission: "…")
      expect(truncated).to end_with("…")
    end
  end

  describe "#to_s" do
    it "includes score and truncated text" do
      str = result.to_s
      expect(str).to include("0.950")
      expect(str).to include("Ruby is")
    end
  end

  describe "#inspect" do
    it "shows class name and key attributes" do
      expect(result.inspect).to include("Leann::SearchResult")
      expect(result.inspect).to include("doc-123")
      expect(result.inspect).to include("0.9500")
    end
  end

  describe "#to_h" do
    it "returns hash representation" do
      hash = result.to_h
      expect(hash[:id]).to eq("doc-123")
      expect(hash[:text]).to eq("Ruby is a dynamic programming language.")
      expect(hash[:score]).to eq(0.95)
      expect(hash[:metadata]).to eq({ source: "readme.md", chapter: 1 })
    end
  end

  describe "#<=>" do
    let(:higher) { described_class.new(id: "1", text: "a", score: 0.99) }
    let(:lower) { described_class.new(id: "2", text: "b", score: 0.50) }

    it "sorts by score descending" do
      results = [lower, higher].sort
      expect(results.first.id).to eq("1")
      expect(results.last.id).to eq("2")
    end
  end

  describe "#==" do
    it "equals same id, text, score" do
      other = described_class.new(id: "doc-123", text: "Ruby is a dynamic programming language.", score: 0.95)
      expect(result).to eq(other)
    end

    it "not equal different score" do
      other = described_class.new(id: "doc-123", text: "Ruby is a dynamic programming language.", score: 0.90)
      expect(result).not_to eq(other)
    end
  end
end

RSpec.describe Leann::SearchResults do
  let(:results) do
    [
      Leann::SearchResult.new(id: "1", text: "First document", score: 0.95),
      Leann::SearchResult.new(id: "2", text: "Second document", score: 0.85),
      Leann::SearchResult.new(id: "3", text: "Third document", score: 0.75)
    ]
  end

  subject(:search_results) { described_class.new(results, query: "test query", duration: 0.123) }

  describe "#each" do
    it "iterates over results" do
      texts = []
      search_results.each { |r| texts << r.text }
      expect(texts).to eq(["First document", "Second document", "Third document"])
    end

    it "is enumerable" do
      expect(search_results.map(&:id)).to eq(%w[1 2 3])
    end
  end

  describe "#size" do
    it "returns count of results" do
      expect(search_results.size).to eq(3)
    end
  end

  describe "#empty?" do
    it "returns false when has results" do
      expect(search_results).not_to be_empty
    end

    it "returns true when empty" do
      empty = described_class.new([])
      expect(empty).to be_empty
    end
  end

  describe "#first" do
    it "returns first result" do
      expect(search_results.first.id).to eq("1")
    end
  end

  describe "#top" do
    it "returns top n results" do
      top2 = search_results.top(2)
      expect(top2.map(&:id)).to eq(%w[1 2])
    end
  end

  describe "#[]" do
    it "returns result by index" do
      expect(search_results[1].id).to eq("2")
    end
  end

  describe "#above" do
    it "filters by minimum score" do
      filtered = search_results.above(0.80)
      expect(filtered.size).to eq(2)
      expect(filtered.map(&:id)).to eq(%w[1 2])
    end

    it "returns new SearchResults instance" do
      filtered = search_results.above(0.80)
      expect(filtered).to be_a(described_class)
      expect(filtered.query).to eq("test query")
    end
  end

  describe "#texts" do
    it "returns all texts" do
      expect(search_results.texts).to eq(["First document", "Second document", "Third document"])
    end
  end

  describe "#combined_text" do
    it "joins texts with separator" do
      combined = search_results.combined_text(separator: " | ")
      expect(combined).to eq("First document | Second document | Third document")
    end
  end

  describe "#to_s" do
    it "includes query and result count" do
      str = search_results.to_s
      expect(str).to include("test query")
      expect(str).to include("3 results")
      expect(str).to include("0.123")
    end
  end

  describe "#to_a" do
    it "returns array of hashes" do
      arr = search_results.to_a
      expect(arr).to be_an(Array)
      expect(arr.first).to be_a(Hash)
      expect(arr.first[:id]).to eq("1")
    end
  end
end

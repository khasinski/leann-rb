# frozen_string_literal: true

RSpec.describe Leann::Searcher do
  let(:index_name) { "test_searcher_#{Time.now.to_i}" }
  let(:index_path) { "#{index_name}.leann" }

  let(:sample_metadata) do
    {
      version: "1.0",
      name: index_name,
      backend: "leann",
      embedding_provider: "openai",
      embedding_model: "text-embedding-3-small",
      dimensions: 1536,
      document_count: 5,
      created_at: Time.now.utc.iso8601
    }
  end

  let(:sample_passages) do
    [
      { id: "1", text: "Ruby is a dynamic language", metadata: { category: "programming", level: 1 } },
      { id: "2", text: "Python is great for data science", metadata: { category: "programming", level: 2 } },
      { id: "3", text: "JavaScript runs in browser", metadata: { category: "web", level: 1 } },
      { id: "4", text: "Go is statically typed", metadata: { category: "programming", level: 3 } },
      { id: "5", text: "Rust is memory safe", metadata: { category: "systems", level: 3 } }
    ]
  end

  before do
    Leann.configure do |config|
      config.openai_api_key = "test-api-key"
    end

    # Create sample index files
    File.write("#{index_path}.meta.json", JSON.generate(sample_metadata))

    # Create passages file and offsets
    offsets = {}
    File.open("#{index_path}.passages.jsonl", "w") do |f|
      sample_passages.each do |passage|
        offsets[passage[:id]] = f.tell
        f.puts JSON.generate(passage)
      end
    end

    File.write("#{index_path}.passages.offsets", JSON.generate(offsets))
  end

  after do
    Dir.glob("#{index_name}*").each { |f| FileUtils.rm_rf(f) }
  end

  describe "#initialize" do
    it "stores the index" do
      index = Leann::Index.open(index_name)
      searcher = described_class.new(index)

      expect(searcher.index).to eq(index)
    end
  end

  describe "#search" do
    let(:index) { Leann::Index.open(index_name) }
    subject(:searcher) { described_class.new(index) }

    let(:mock_embedding_provider) do
      double("EmbeddingProvider").tap do |provider|
        allow(provider).to receive(:compute) do |texts|
          texts.map { Array.new(1536) { rand(-1.0..1.0) } }
        end
      end
    end

    let(:mock_backend) do
      double("Backend").tap do |backend|
        allow(backend).to receive(:search) do |_query, embedding_provider:, passages:, limit:|
          # Return mock results (id, score pairs)
          sample_passages.first(limit).map.with_index do |p, i|
            [p[:id], 0.9 - (i * 0.1)]
          end
        end
      end
    end

    before do
      allow(searcher).to receive(:embedding_provider).and_return(mock_embedding_provider)
      allow(searcher).to receive(:backend).and_return(mock_backend)
    end

    it "returns SearchResults" do
      results = searcher.search("query")
      expect(results).to be_a(Leann::SearchResults)
    end

    it "returns correct number of results" do
      results = searcher.search("query", limit: 3)
      expect(results.size).to eq(3)
    end

    it "returns SearchResult objects" do
      results = searcher.search("query", limit: 1)
      expect(results.first).to be_a(Leann::SearchResult)
    end

    it "includes text and metadata" do
      results = searcher.search("query", limit: 1)
      result = results.first

      expect(result.text).to eq("Ruby is a dynamic language")
      expect(result.metadata[:category]).to eq("programming")
    end

    it "sorts by score descending" do
      results = searcher.search("query", limit: 5)

      scores = results.map(&:score)
      expect(scores).to eq(scores.sort.reverse)
    end

    it "stores query in results" do
      results = searcher.search("test query")
      expect(results.query).to eq("test query")
    end

    it "tracks duration" do
      results = searcher.search("query")
      expect(results.duration).to be_a(Float)
      expect(results.duration).to be >= 0
    end

    context "with threshold" do
      it "filters results below threshold" do
        results = searcher.search("query", limit: 10, threshold: 0.75)

        results.each do |result|
          expect(result.score).to be >= 0.75
        end
      end

      it "may return fewer results than limit" do
        results = searcher.search("query", limit: 10, threshold: 0.85)

        expect(results.size).to be < 10
      end
    end

    context "with metadata filters" do
      it "filters by exact value" do
        results = searcher.search("query", limit: 10, filters: { category: "programming" })

        results.each do |result|
          expect(result.metadata[:category]).to eq("programming")
        end
      end

      it "filters by range" do
        results = searcher.search("query", limit: 10, filters: { level: 1..2 })

        results.each do |result|
          expect(result.metadata[:level]).to be_between(1, 2)
        end
      end

      it "filters by array of values" do
        results = searcher.search("query", limit: 10, filters: { category: ["web", "systems"] })

        results.each do |result|
          expect(["web", "systems"]).to include(result.metadata[:category])
        end
      end

      it "filters by regex" do
        results = searcher.search("query", limit: 10, filters: { category: /program/ })

        results.each do |result|
          expect(result.metadata[:category]).to match(/program/)
        end
      end

      it "combines multiple filters" do
        results = searcher.search("query", limit: 10, filters: { category: "programming", level: 1..2 })

        results.each do |result|
          expect(result.metadata[:category]).to eq("programming")
          expect(result.metadata[:level]).to be_between(1, 2)
        end
      end
    end
  end

  describe "private methods" do
    let(:index) { Leann::Index.open(index_name) }
    subject(:searcher) { described_class.new(index) }

    describe "#load_passage" do
      it "loads passage by id using offset" do
        passage = searcher.send(:load_passage, "2")

        expect(passage[:text]).to eq("Python is great for data science")
        expect(passage[:metadata][:category]).to eq("programming")
      end

      it "returns nil for unknown id" do
        expect(searcher.send(:load_passage, "unknown")).to be_nil
      end

      context "without offsets file" do
        before do
          FileUtils.rm("#{index_path}.passages.offsets")
        end

        it "falls back to linear scan" do
          passage = searcher.send(:load_passage, "3")
          expect(passage[:text]).to eq("JavaScript runs in browser")
        end
      end
    end

    describe "#apply_filters" do
      let(:results) do
        sample_passages.map do |p|
          Leann::SearchResult.new(
            id: p[:id],
            text: p[:text],
            score: 1.0,
            metadata: p[:metadata]
          )
        end
      end

      it "filters with exact match" do
        filtered = searcher.send(:apply_filters, results, { category: "web" })
        expect(filtered.size).to eq(1)
        expect(filtered.first.metadata[:category]).to eq("web")
      end

      it "filters with Range" do
        filtered = searcher.send(:apply_filters, results, { level: 2..3 })
        expect(filtered.size).to eq(3)
      end

      it "filters with Array" do
        filtered = searcher.send(:apply_filters, results, { category: %w[web systems] })
        expect(filtered.size).to eq(2)
      end

      it "filters with Regexp" do
        filtered = searcher.send(:apply_filters, results, { text: /dynamic/ })
        expect(filtered.size).to eq(0) # metadata doesn't have text
      end
    end
  end
end

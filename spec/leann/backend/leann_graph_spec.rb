# frozen_string_literal: true

require_relative "../../../lib/leann/backend/leann_graph"

RSpec.describe Leann::Backend::LeannGraph do
  let(:graph_name) { "test_graph_#{Time.now.to_i}" }

  after do
    Dir.glob("#{graph_name}*").each { |f| FileUtils.rm_rf(f) }
  end

  describe "#initialize" do
    it "sets dimensions" do
      graph = described_class.new(dimensions: 384)
      expect(graph.dimensions).to eq(384)
    end

    it "sets default M parameter" do
      graph = described_class.new(dimensions: 384)
      expect(graph.m).to eq(16)
    end

    it "sets default ef_construction" do
      graph = described_class.new(dimensions: 384)
      expect(graph.ef_construction).to eq(200)
    end

    it "allows custom M parameter" do
      graph = described_class.new(dimensions: 384, m: 32)
      expect(graph.m).to eq(32)
    end

    it "initializes with zero nodes" do
      graph = described_class.new(dimensions: 384)
      expect(graph.node_count).to eq(0)
    end
  end

  describe "#build" do
    let(:ids) { %w[doc1 doc2 doc3] }
    let(:embeddings) do
      [
        Array.new(384) { rand(-1.0..1.0) },
        Array.new(384) { rand(-1.0..1.0) },
        Array.new(384) { rand(-1.0..1.0) }
      ]
    end

    it "builds graph from embeddings" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      expect(graph.node_count).to eq(3)
    end

    it "raises on mismatched ids and embeddings" do
      graph = described_class.new(dimensions: 384)
      expect do
        graph.build(ids, embeddings[0..1])
      end.to raise_error(ArgumentError, /same length/)
    end

    it "handles empty input" do
      graph = described_class.new(dimensions: 384)
      graph.build([], [])

      expect(graph.node_count).to eq(0)
    end

    it "sets entry point" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      expect(graph.entry_point).not_to be_nil
    end

    it "returns self for chaining" do
      graph = described_class.new(dimensions: 384)
      result = graph.build(ids, embeddings)

      expect(result).to be(graph)
    end
  end

  describe "#save and .load" do
    let(:ids) { %w[doc1 doc2 doc3 doc4 doc5] }
    let(:embeddings) do
      ids.map { Array.new(384) { rand(-1.0..1.0) } }
    end

    it "saves graph to binary file" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)
      graph.save(graph_name)

      expect(File.exist?("#{graph_name}.graph.bin")).to be true
      expect(File.exist?("#{graph_name}.graph.meta.json")).to be true
    end

    it "saves metadata" do
      graph = described_class.new(dimensions: 384, m: 32)
      graph.build(ids, embeddings)
      graph.save(graph_name)

      meta = JSON.parse(File.read("#{graph_name}.graph.meta.json"))
      expect(meta["node_count"]).to eq(5)
      expect(meta["dimensions"]).to eq(384)
      expect(meta["m"]).to eq(32)
    end

    it "loads graph from files" do
      original = described_class.new(dimensions: 384)
      original.build(ids, embeddings)
      original.save(graph_name)

      loaded = described_class.load(graph_name)

      expect(loaded.node_count).to eq(5)
      expect(loaded.dimensions).to eq(384)
      expect(loaded.entry_point).to eq(original.entry_point)
    end

    it "preserves node IDs after load" do
      original = described_class.new(dimensions: 384)
      original.build(ids, embeddings)
      original.save(graph_name)

      loaded = described_class.load(graph_name)

      expect(loaded.get_id(0)).to eq("doc1")
      expect(loaded.get_idx("doc3")).to eq(2)
    end

    it "raises on missing file" do
      expect do
        described_class.load("nonexistent")
      end.to raise_error(Leann::IndexNotFoundError)
    end
  end

  describe "#search" do
    let(:ids) { %w[ruby python javascript go rust] }
    let(:texts) do
      {
        "ruby" => "Ruby is a dynamic programming language",
        "python" => "Python is great for data science",
        "javascript" => "JavaScript runs in the browser",
        "go" => "Go is fast and simple",
        "rust" => "Rust is memory safe"
      }
    end

    let(:mock_provider) do
      double("EmbeddingProvider").tap do |provider|
        allow(provider).to receive(:compute_one) do |text|
          # Simple hash-based mock embedding
          Array.new(384) { |i| ((text.bytes.sum + i) % 256 / 256.0) - 0.5 }
        end
        allow(provider).to receive(:compute) do |texts|
          texts.map { |t| Array.new(384) { |i| ((t.bytes.sum + i) % 256 / 256.0) - 0.5 } }
        end
      end
    end

    let(:embeddings) do
      texts.values.map { |t| Array.new(384) { |i| ((t.bytes.sum + i) % 256 / 256.0) - 0.5 } }
    end

    it "returns search results" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      query_embedding = Array.new(384) { |i| (("Ruby language".bytes.sum + i) % 256 / 256.0) - 0.5 }

      results = graph.search(
        query_embedding,
        embedding_provider: mock_provider,
        passages: texts,
        limit: 3
      )

      expect(results).to be_an(Array)
      expect(results.size).to be <= 3
    end

    it "returns [id, score] pairs" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      query_embedding = embeddings.first
      results = graph.search(
        query_embedding,
        embedding_provider: mock_provider,
        passages: texts,
        limit: 3
      )

      results.each do |id, score|
        expect(id).to be_a(String)
        expect(score).to be_a(Float)
        expect(score).to be_between(0, 1)
      end
    end

    it "returns empty array for empty graph" do
      graph = described_class.new(dimensions: 384)

      results = graph.search(
        Array.new(384) { 0.0 },
        embedding_provider: mock_provider,
        passages: {},
        limit: 3
      )

      expect(results).to eq([])
    end
  end

  describe "#get_neighbors" do
    let(:ids) { %w[a b c] }
    let(:embeddings) do
      ids.map { Array.new(384) { rand(-1.0..1.0) } }
    end

    it "returns neighbor indices" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      # At least some nodes should have neighbors at level 0
      neighbors = graph.get_neighbors(0, 0)
      expect(neighbors).to be_an(Array)
    end

    it "returns empty array for invalid node" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      expect(graph.get_neighbors(999, 0)).to eq([])
    end

    it "returns empty array for invalid level" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      expect(graph.get_neighbors(0, 999)).to eq([])
    end
  end

  describe "#get_id / #get_idx" do
    let(:ids) { %w[doc_a doc_b doc_c] }
    let(:embeddings) do
      ids.map { Array.new(384) { rand(-1.0..1.0) } }
    end

    it "maps index to id" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      expect(graph.get_id(0)).to eq("doc_a")
      expect(graph.get_id(1)).to eq("doc_b")
      expect(graph.get_id(2)).to eq("doc_c")
    end

    it "maps id to index" do
      graph = described_class.new(dimensions: 384)
      graph.build(ids, embeddings)

      expect(graph.get_idx("doc_a")).to eq(0)
      expect(graph.get_idx("doc_b")).to eq(1)
      expect(graph.get_idx("doc_c")).to eq(2)
    end
  end
end

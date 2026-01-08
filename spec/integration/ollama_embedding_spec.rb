# frozen_string_literal: true

RSpec.describe "Ollama Embedding Integration", :integration do
  before do
    skip "Ollama not running" unless has_ollama?
  end

  describe Leann::Embedding::Ollama do
    subject(:provider) { described_class.new(model: "all-minilm") }

    it "computes embeddings for texts" do
      texts = ["Hello, world!", "Ruby is great"]
      embeddings = provider.compute(texts)

      expect(embeddings).to be_an(Array)
      expect(embeddings.size).to eq(2)
      expect(embeddings.first).to be_an(Array)
      expect(embeddings.first.size).to be > 100 # nomic-embed-text has 768 dimensions
    end

    it "computes single embedding" do
      embedding = provider.compute_one("Test document about Ruby programming")

      expect(embedding).to be_an(Array)
      expect(embedding.size).to be > 100
      expect(embedding.first).to be_a(Float)
    end

    it "normalizes embeddings" do
      embedding = provider.compute_one("Normalized vector")

      # Check L2 norm is approximately 1
      norm = Math.sqrt(embedding.sum { |x| x * x })
      expect(norm).to be_within(0.01).of(1.0)
    end

    it "handles batch of documents" do
      texts = sample_documents
      embeddings = provider.compute(texts)

      expect(embeddings.size).to eq(5)
      embeddings.each do |emb|
        expect(emb).to be_an(Array)
        expect(emb.size).to be > 100
      end
    end
  end
end

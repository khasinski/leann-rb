# frozen_string_literal: true

# Mock Fastembed module for testing
module Fastembed
  class Error < StandardError; end

  class TextEmbedding
    attr_reader :model_name, :cache_dir, :threads

    def initialize(model_name: "BAAI/bge-small-en-v1.5", cache_dir: nil, threads: nil)
      @model_name = model_name
      @cache_dir = cache_dir
      @threads = threads
    end

    def embed(texts, batch_size: 64)
      # Return mock 384-dimensional embeddings
      texts.map do |_text|
        Array.new(384) { rand(-1.0..1.0) }
      end
    end
  end
end

require "spec_helper"
require "leann/embedding/fastembed"

RSpec.describe Leann::Embedding::FastEmbed do
  let(:provider) { described_class.new }

  describe "#initialize" do
    it "uses default model" do
      expect(provider.model).to eq("BAAI/bge-small-en-v1.5")
    end

    it "accepts custom model" do
      custom = described_class.new(model: "BAAI/bge-base-en-v1.5")
      expect(custom.model).to eq("BAAI/bge-base-en-v1.5")
    end

    it "accepts cache_dir option" do
      custom = described_class.new(cache_dir: "/tmp/models")
      expect(custom.instance_variable_get(:@cache_dir)).to eq("/tmp/models")
    end

    it "accepts threads option" do
      custom = described_class.new(threads: 4)
      expect(custom.instance_variable_get(:@threads)).to eq(4)
    end
  end

  describe "#compute" do
    it "returns empty array for empty input" do
      expect(provider.compute([])).to eq([])
    end

    it "returns embeddings for texts" do
      texts = ["Hello world", "Test text"]
      embeddings = provider.compute(texts)

      expect(embeddings.size).to eq(2)
      expect(embeddings[0].size).to eq(384)
      expect(embeddings[1].size).to eq(384)
    end

    it "returns arrays of floats" do
      embeddings = provider.compute(["Test"])

      expect(embeddings[0]).to all(be_a(Float))
    end
  end

  describe "#compute_one" do
    it "returns single embedding" do
      embedding = provider.compute_one("Hello world")

      expect(embedding).to be_an(Array)
      expect(embedding.size).to eq(384)
    end
  end

  describe "#dimensions" do
    it "returns 384 for default model" do
      expect(provider.dimensions).to eq(384)
    end

    it "returns 768 for bge-base model" do
      custom = described_class.new(model: "BAAI/bge-base-en-v1.5")
      expect(custom.dimensions).to eq(768)
    end
  end

  describe "MODELS" do
    it "includes common models" do
      expect(described_class::MODELS).to include(
        "BAAI/bge-small-en-v1.5" => 384,
        "BAAI/bge-base-en-v1.5" => 768,
        "intfloat/multilingual-e5-small" => 384,
        "nomic-ai/nomic-embed-text-v1.5" => 768
      )
    end
  end

  describe "batch processing" do
    it "handles batches larger than MAX_BATCH_SIZE" do
      texts = Array.new(100) { |i| "Document #{i}" }
      embeddings = provider.compute(texts)

      expect(embeddings.size).to eq(100)
    end
  end

  context "when Fastembed gem is not available" do
    before do
      hide_const("Fastembed")
    end

    it "raises ConfigurationError" do
      expect { described_class.new }.to raise_error(
        Leann::ConfigurationError,
        /FastEmbed gem is required/
      )
    end
  end
end

# frozen_string_literal: true

# Mock RubyLLM module for testing
module RubyLLM
  class Error < StandardError; end

  class EmbeddingResult
    attr_reader :vectors

    def initialize(vectors)
      @vectors = vectors
    end
  end

  class << self
    attr_accessor :mock_vectors, :should_raise

    def embed(texts, **_options)
      raise Error, "Mock error" if should_raise

      vectors = texts.map do |_text|
        mock_vectors || Array.new(1536) { rand(-1.0..1.0) }
      end
      EmbeddingResult.new(vectors)
    end

    def reset_mock!
      @mock_vectors = nil
      @should_raise = false
    end
  end
end

require_relative "../../../lib/leann/embedding/ruby_llm"

RSpec.describe Leann::Embedding::RubyLLM do
  before do
    RubyLLM.reset_mock!
  end

  describe "#initialize" do
    it "initializes without model" do
      provider = described_class.new
      expect(provider).to be_a(described_class)
    end

    it "accepts custom model" do
      provider = described_class.new(model: "text-embedding-3-large")
      expect(provider.instance_variable_get(:@model)).to eq("text-embedding-3-large")
    end
  end

  describe "#compute" do
    subject(:provider) { described_class.new }

    it "returns empty array for empty input" do
      expect(provider.compute([])).to eq([])
    end

    it "returns embeddings for texts" do
      RubyLLM.mock_vectors = Array.new(1536) { 0.5 }

      result = provider.compute(["Hello world"])

      expect(result).to be_an(Array)
      expect(result.size).to eq(1)
      expect(result.first.size).to eq(1536)
    end

    it "handles multiple texts" do
      result = provider.compute(%w[One Two Three])

      expect(result.size).to eq(3)
    end

    it "wraps single string in array" do
      result = provider.compute("Single text")

      expect(result.size).to eq(1)
    end

    it "raises EmbeddingError on RubyLLM error" do
      RubyLLM.should_raise = true

      expect do
        provider.compute(["test"])
      end.to raise_error(Leann::EmbeddingError, /RubyLLM embedding failed/)
    end
  end

  describe "#dimensions" do
    subject(:provider) { described_class.new }

    it "returns dimensions from test embedding" do
      RubyLLM.mock_vectors = Array.new(384) { 0.1 }

      expect(provider.dimensions).to eq(384)
    end

    it "caches dimensions" do
      RubyLLM.mock_vectors = Array.new(1536) { 0.1 }
      provider.dimensions

      RubyLLM.mock_vectors = Array.new(768) { 0.1 }
      expect(provider.dimensions).to eq(1536) # Should still be cached
    end
  end

  describe "#provider_name" do
    it "returns :ruby_llm" do
      provider = described_class.new
      expect(provider.provider_name).to eq(:ruby_llm)
    end
  end
end

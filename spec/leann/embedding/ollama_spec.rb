# frozen_string_literal: true

RSpec.describe Leann::Embedding::Ollama do
  before do
    # Stub version check to simulate running Ollama
    stub_request(:get, "http://localhost:11434/api/version")
      .to_return(status: 200, body: { version: "0.1.0" }.to_json)
  end

  describe "constants" do
    it "defines DEFAULT_HOST" do
      expect(described_class::DEFAULT_HOST).to eq("http://localhost:11434")
    end

    it "defines MAX_BATCH_SIZE" do
      expect(described_class::MAX_BATCH_SIZE).to eq(32)
    end

    it "defines POPULAR_MODELS" do
      expect(described_class::POPULAR_MODELS).to include("nomic-embed-text")
      expect(described_class::POPULAR_MODELS).to include("all-minilm")
    end
  end

  describe "#initialize" do
    it "sets default model" do
      provider = described_class.new
      expect(provider.model).to eq("nomic-embed-text")
    end

    it "allows custom model" do
      provider = described_class.new(model: "all-minilm")
      expect(provider.model).to eq("all-minilm")
    end

    it "uses default host" do
      provider = described_class.new
      expect(provider.instance_variable_get(:@host)).to eq("http://localhost:11434")
    end

    it "allows custom host" do
      stub_request(:get, "http://custom:9999/api/version")
        .to_return(status: 200, body: {}.to_json)

      provider = described_class.new(host: "http://custom:9999")
      expect(provider.instance_variable_get(:@host)).to eq("http://custom:9999")
    end

    it "uses host from configuration" do
      Leann.configure { |c| c.ollama_host = "http://config:8080" }
      stub_request(:get, "http://config:8080/api/version")
        .to_return(status: 200, body: {}.to_json)

      provider = described_class.new
      expect(provider.instance_variable_get(:@host)).to eq("http://config:8080")

      Leann.configure { |c| c.ollama_host = nil }
    end

    it "uses host from ENV" do
      Leann.configure { |c| c.ollama_host = nil }
      allow(ENV).to receive(:[]).with("OLLAMA_HOST").and_return("http://env:7777")
      stub_request(:get, "http://env:7777/api/version")
        .to_return(status: 200, body: {}.to_json)

      provider = described_class.new
      expect(provider.instance_variable_get(:@host)).to eq("http://env:7777")
    end

    it "raises EmbeddingError if Ollama not running" do
      stub_request(:get, "http://localhost:11434/api/version")
        .to_timeout

      expect {
        described_class.new
      }.to raise_error(Leann::EmbeddingError, /Cannot connect/)
    end
  end

  describe "#compute" do
    subject(:provider) { described_class.new }

    before do
      stub_request(:post, "http://localhost:11434/api/embed")
        .to_return(
          status: 200,
          body: {
            embeddings: [
              Array.new(384) { 0.1 },
              Array.new(384) { 0.2 }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns empty array for empty input" do
      result = provider.compute([])
      expect(result).to eq([])
    end

    it "makes request to Ollama API" do
      provider.compute(["Hello", "World"])

      expect(WebMock).to have_requested(:post, "http://localhost:11434/api/embed")
        .with(
          body: hash_including(
            "model" => "nomic-embed-text",
            "input" => ["Hello", "World"]
          )
        )
    end

    it "returns embeddings" do
      result = provider.compute(["Hello", "World"])

      expect(result.size).to eq(2)
    end

    it "normalizes embeddings" do
      result = provider.compute(["Hello", "World"])

      result.each do |embedding|
        norm = Math.sqrt(embedding.sum { |x| x * x })
        expect(norm).to be_within(0.01).of(1.0)
      end
    end
  end

  describe "error handling" do
    subject(:provider) { described_class.new }

    it "raises EmbeddingError on model not found" do
      stub_request(:post, "http://localhost:11434/api/embed")
        .to_return(status: 404, body: "model not found")

      expect {
        provider.compute(["test"])
      }.to raise_error(Leann::EmbeddingError, /not found/)
    end

    it "raises EmbeddingError on API error" do
      stub_request(:post, "http://localhost:11434/api/embed")
        .to_return(
          status: 500,
          body: { error: "internal error" }.to_json
        )

      expect {
        provider.compute(["test"])
      }.to raise_error(Leann::EmbeddingError, /error/)
    end

    it "raises EmbeddingError on invalid response" do
      stub_request(:post, "http://localhost:11434/api/embed")
        .to_return(
          status: 200,
          body: { embeddings: nil }.to_json
        )

      expect {
        provider.compute(["test"])
      }.to raise_error(Leann::EmbeddingError, /Invalid response/)
    end

    it "raises EmbeddingError on count mismatch" do
      stub_request(:post, "http://localhost:11434/api/embed")
        .to_return(
          status: 200,
          body: { embeddings: [[0.1]] }.to_json
        )

      expect {
        provider.compute(["one", "two"])
      }.to raise_error(Leann::EmbeddingError, /expected 2/)
    end

    it "raises EmbeddingError on parse failure" do
      stub_request(:post, "http://localhost:11434/api/embed")
        .to_return(status: 200, body: "not json")

      expect {
        provider.compute(["test"])
      }.to raise_error(Leann::EmbeddingError, /parse/)
    end
  end
end

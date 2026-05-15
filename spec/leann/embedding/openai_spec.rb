# frozen_string_literal: true

RSpec.describe Leann::Embedding::OpenAI do
  before do
    Leann.configure do |config|
      config.openai_api_key = "test-api-key"
    end
  end

  describe "constants" do
    it "defines BASE_URL" do
      expect(described_class::BASE_URL).to eq("https://api.openai.com/v1/embeddings")
    end

    it "defines MAX_BATCH_SIZE" do
      expect(described_class::MAX_BATCH_SIZE).to eq(2048)
    end

    it "defines DIMENSIONS for known models" do
      expect(described_class::DIMENSIONS["text-embedding-3-small"]).to eq(1536)
      expect(described_class::DIMENSIONS["text-embedding-3-large"]).to eq(3072)
      expect(described_class::DIMENSIONS["text-embedding-ada-002"]).to eq(1536)
    end
  end

  describe "#initialize" do
    it "sets default model" do
      provider = described_class.new
      expect(provider.model).to eq("text-embedding-3-small")
    end

    it "allows custom model" do
      provider = described_class.new(model: "text-embedding-3-large")
      expect(provider.model).to eq("text-embedding-3-large")
    end

    it "sets dimensions based on model" do
      provider = described_class.new(model: "text-embedding-3-small")
      expect(provider.dimensions).to eq(1536)
    end

    it "uses api_key from parameter" do
      provider = described_class.new(api_key: "explicit-key")
      expect(provider.instance_variable_get(:@api_key)).to eq("explicit-key")
    end

    it "uses api_key from configuration" do
      Leann.configure { |c| c.openai_api_key = "config-key" }
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("config-key")
    end

    it "uses api_key from ENV" do
      original = ENV.delete("OPENAI_API_KEY")
      ENV["OPENAI_API_KEY"] = "env-key"
      Leann.configure { |c| c.openai_api_key = nil }
      provider = described_class.new
      expect(provider.instance_variable_get(:@api_key)).to eq("env-key")
    ensure
      ENV["OPENAI_API_KEY"] = original
    end

    it "raises ConfigurationError without API key" do
      original = ENV.delete("OPENAI_API_KEY")
      Leann.configure { |c| c.openai_api_key = nil }

      expect do
        described_class.new
      end.to raise_error(Leann::ConfigurationError, /API key is required/)
    ensure
      ENV["OPENAI_API_KEY"] = original
    end

    it "allows custom base_url" do
      provider = described_class.new(base_url: "https://custom.api.com/v1/embeddings")
      expect(provider.instance_variable_get(:@base_url)).to eq("https://custom.api.com/v1/embeddings")
    end
  end

  describe "#compute" do
    subject(:provider) { described_class.new }

    before do
      # Stub successful API response
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(
          status: 200,
          body: {
            data: [
              { index: 0, embedding: Array.new(1536) { 0.1 } },
              { index: 1, embedding: Array.new(1536) { 0.2 } }
            ]
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns empty array for empty input" do
      result = provider.compute([])
      expect(result).to eq([])
    end

    it "makes request to OpenAI API" do
      provider.compute(%w[Hello World])

      expect(WebMock).to have_requested(:post, "https://api.openai.com/v1/embeddings")
        .with(
          body: hash_including(
            "model" => "text-embedding-3-small",
            "input" => %w[Hello World]
          )
        )
    end

    it "returns embeddings in order" do
      result = provider.compute(%w[Hello World])

      expect(result.size).to eq(2)
      expect(result[0]).to all(eq(0.1))
      expect(result[1]).to all(eq(0.2))
    end

    it "handles out-of-order response" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(
          status: 200,
          body: {
            data: [
              { index: 1, embedding: [0.2] },
              { index: 0, embedding: [0.1] }
            ]
          }.to_json
        )

      result = provider.compute(%w[A B])
      expect(result).to eq([[0.1], [0.2]])
    end
  end

  describe "error handling" do
    subject(:provider) { described_class.new }

    it "raises EmbeddingError on API error" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(
          status: 400,
          body: { error: { message: "Invalid input" } }.to_json
        )

      expect do
        provider.compute(["test"])
      end.to raise_error(Leann::EmbeddingError, /Invalid input/)
    end

    it "raises EmbeddingError on parse failure" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(
          status: 200,
          body: "not json"
        )

      expect do
        provider.compute(["test"])
      end.to raise_error(Leann::EmbeddingError, /parse/)
    end

    it "retries on rate limit" do
      attempts = 0
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return do |_|
          attempts += 1
          if attempts < 2
            { status: 429, body: "rate limited" }
          else
            {
              status: 200,
              body: { data: [{ index: 0, embedding: [0.1] }] }.to_json
            }
          end
        end

      # Speed up test by stubbing sleep
      allow(provider).to receive(:sleep)

      result = provider.compute(["test"])
      expect(result).to eq([[0.1]])
      expect(attempts).to eq(2)
    end

    it "gives up after MAX_RETRIES" do
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .to_return(status: 429, body: "rate limited")

      allow(provider).to receive(:sleep)

      expect do
        provider.compute(["test"])
      end.to raise_error(Leann::EmbeddingError, /retries/)
    end
  end
end

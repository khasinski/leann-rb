# frozen_string_literal: true

RSpec.describe "OpenAI Embedding Integration", :integration do
  before do
    skip "OPENAI_API_KEY not set" unless has_openai_key?
  end

  describe Leann::Embedding::OpenAI do
    subject(:provider) { described_class.new(model: "text-embedding-3-small") }

    it "computes embeddings for texts", :vcr do
      VCR.use_cassette("openai/embeddings_basic") do
        texts = ["Hello, world!", "Ruby is great"]
        embeddings = provider.compute(texts)

        expect(embeddings).to be_an(Array)
        expect(embeddings.size).to eq(2)
        expect(embeddings.first).to be_an(Array)
        expect(embeddings.first.size).to eq(1536) # text-embedding-3-small dimensions
      end
    end

    it "computes single embedding", :vcr do
      VCR.use_cassette("openai/embedding_single") do
        embedding = provider.compute_one("Test document")

        expect(embedding).to be_an(Array)
        expect(embedding.size).to eq(1536)
        expect(embedding.first).to be_a(Float)
      end
    end

    it "handles batch of documents", :vcr do
      VCR.use_cassette("openai/embeddings_batch") do
        texts = sample_documents
        embeddings = provider.compute(texts)

        expect(embeddings.size).to eq(5)
        embeddings.each do |emb|
          expect(emb.size).to eq(1536)
        end
      end
    end
  end
end

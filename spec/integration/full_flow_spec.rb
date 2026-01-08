# frozen_string_literal: true

RSpec.describe "Full Flow Integration", :integration do
  let(:index_name) { "test_integration_#{Time.now.to_i}" }

  after do
    FileUtils.rm_rf("#{index_name}.leann")
    Dir.glob("#{index_name}.leann*").each { |f| FileUtils.rm_rf(f) }
  end

  context "with OpenAI" do
    before do
      skip "OPENAI_API_KEY not set" unless has_openai_key?
    end

    describe "build and search flow", :vcr do
      it "builds index and searches" do
        VCR.use_cassette("openai/full_flow_build_search") do
          index = Leann.build(index_name, embedding: :openai) do
            add "Ruby is a dynamic programming language focused on simplicity."
            add "Python is known for its readability and versatility."
            add "JavaScript runs in the browser and on servers with Node.js."
          end

          expect(index).to be_a(Leann::Index)
          expect(index.document_count).to eq(3)
          expect(index.embedding_model).to eq("text-embedding-3-small")

          # Search
          results = Leann.search(index_name, "dynamic programming language")

          expect(results).not_to be_empty
          expect(results.first.text).to include("Ruby")
          expect(results.first.score).to be > 0.4
        end
      end
    end
  end

  context "with Ollama" do
    before do
      skip "Ollama not running" unless has_ollama?
    end

    describe "build and search flow" do
      it "builds index and searches locally" do
        index = Leann.build(index_name, embedding: :ollama, model: "all-minilm") do
          add "Ruby is a dynamic programming language focused on simplicity."
          add "Python is known for its readability and versatility."
          add "JavaScript runs in the browser and on servers with Node.js."
        end

        expect(index).to be_a(Leann::Index)
        expect(index.document_count).to eq(3)
        expect(index.embedding_provider).to eq(:ollama)

        # Search
        results = Leann.search(index_name, "dynamic programming language")

        expect(results).not_to be_empty
        expect(results.size).to be <= 5
      end
    end
  end
end

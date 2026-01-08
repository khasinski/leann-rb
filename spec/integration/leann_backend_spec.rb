# frozen_string_literal: true

RSpec.describe "LEANN Backend Integration", :integration do
  let(:index_name) { "test_leann_#{Time.now.to_i}" }

  after do
    FileUtils.rm_rf("#{index_name}.leann")
    Dir.glob("#{index_name}.leann*").each { |f| FileUtils.rm_rf(f) }
  end

  context "with Ollama" do
    before do
      skip "Ollama not running" unless has_ollama?
    end

    describe "build and search flow with LEANN backend" do
      it "builds graph-only index and searches with embedding recomputation" do
        # Build with LEANN backend (graph-only, no embeddings stored)
        index = Leann.build(index_name, embedding: :ollama, model: "all-minilm") do
          add "Ruby is a dynamic programming language focused on simplicity."
          add "Python is known for its readability and versatility."
          add "JavaScript runs in the browser and on servers with Node.js."
          add "Go is a statically typed language designed at Google."
          add "Rust focuses on memory safety without garbage collection."
        end

        expect(index).to be_a(Leann::Index)
        expect(index.document_count).to eq(5)
        expect(index.backend).to eq(:leann)

        # Verify graph files exist
        expect(File.exist?("#{index_name}.leann.graph.bin")).to be true
        expect(File.exist?("#{index_name}.leann.graph.meta.json")).to be true

        # Verify storage savings - graph file should be much smaller than embeddings would be
        graph_size = File.size("#{index_name}.leann.graph.bin")
        # With 5 documents, ~384 dimensions, embeddings would be ~7680 bytes (5 * 384 * 4)
        # Graph should be significantly smaller (just neighbor lists)
        expect(graph_size).to be < 5000  # Graph should be under 5KB for 5 docs

        # Search (this recomputes embeddings on-the-fly)
        results = Leann.search(index_name, "dynamic programming language")

        expect(results).not_to be_empty
        expect(results.first.text).to include("Ruby")
        expect(results.first.score).to be > 0.3
      end
    end
  end

  context "with OpenAI" do
    before do
      skip "OPENAI_API_KEY not set" unless has_openai_key?
    end

    describe "build and search flow with LEANN backend", :vcr do
      it "builds graph-only index and searches" do
        VCR.use_cassette("openai/leann_backend_build_search") do
          index = Leann.build(index_name, embedding: :openai) do
            add "LEANN saves 85-96% storage compared to traditional vector databases."
            add "It uses HNSW algorithm for fast approximate nearest neighbor search."
            add "The gem supports both OpenAI and Ollama for embeddings."
          end

          expect(index.backend).to eq(:leann)
          expect(index.document_count).to eq(3)

          # Search with embedding recomputation
          results = Leann.search(index_name, "storage savings")

          expect(results).not_to be_empty
          expect(results.first.text).to include("85-96%")
        end
      end
    end
  end
end

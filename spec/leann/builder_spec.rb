# frozen_string_literal: true

# Load embedding module for mocking
require_relative "../../lib/leann/embedding/base"
require_relative "../../lib/leann/embedding/openai"

RSpec.describe Leann::Builder do
  let(:index_name) { "test_builder_#{Time.now.to_i}" }

  # Mock embedding provider for unit tests
  let(:mock_provider) do
    double("EmbeddingProvider").tap do |provider|
      allow(provider).to receive(:compute) do |texts|
        texts.map { Array.new(1536) { rand(-1.0..1.0) } }
      end
    end
  end

  before do
    Leann.configure do |config|
      config.openai_api_key = "test-key"
    end
  end

  after do
    Dir.glob("#{index_name}*").each { |f| FileUtils.rm_rf(f) }
  end

  describe "#initialize" do
    it "sets index name" do
      builder = described_class.new(index_name)
      expect(builder.name).to eq(index_name)
    end

    it "sets default embedding provider based on RubyLLM availability" do
      builder = described_class.new(index_name)
      expected = Leann.configuration.ruby_llm_available? ? :ruby_llm : :openai
      expect(builder.instance_variable_get(:@embedding_provider)).to eq(expected)
    end

    it "uses leann backend (only backend available)" do
      builder = described_class.new(index_name)
      # LEANN is the only backend, no @backend instance variable needed
      expect(builder).to respond_to(:save)
    end

    it "allows custom embedding provider" do
      builder = described_class.new(index_name, embedding: :ollama)
      expect(builder.instance_variable_get(:@embedding_provider)).to eq(:ollama)
    end

    it "raises if index exists without force" do
      # Create a dummy index file
      FileUtils.mkdir_p("#{index_name}.leann")
      File.write("#{index_name}.leann.meta.json", "{}")

      expect do
        described_class.new(index_name)
      end.to raise_error(Leann::IndexExistsError)
    end

    it "allows force overwrite" do
      FileUtils.mkdir_p("#{index_name}.leann")
      File.write("#{index_name}.leann.meta.json", "{}")

      expect do
        described_class.new(index_name, force: true)
      end.not_to raise_error
    end
  end

  describe "#add" do
    subject(:builder) { described_class.new(index_name) }

    it "adds document" do
      builder.add("Test document")
      expect(builder.count).to eq(1)
    end

    it "generates UUID for document" do
      builder.add("Test document")
      doc = builder.documents.first
      expect(doc[:id]).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "stores text" do
      builder.add("Test document")
      expect(builder.documents.first[:text]).to eq("Test document")
    end

    it "stores metadata" do
      builder.add("Test", source: "file.md", chapter: 1)
      doc = builder.documents.first
      expect(doc[:metadata][:source]).to eq("file.md")
      expect(doc[:metadata][:chapter]).to eq(1)
    end

    it "allows custom id" do
      builder.add("Test", id: "custom-id")
      expect(builder.documents.first[:id]).to eq("custom-id")
    end

    it "returns self for chaining" do
      result = builder.add("One")
      expect(result).to be(builder)
    end

    it "raises on nil text" do
      expect { builder.add(nil) }.to raise_error(ArgumentError, /nil/)
    end

    it "raises on empty text" do
      expect { builder.add("   ") }.to raise_error(ArgumentError, /empty/)
    end

    it "strips whitespace" do
      builder.add("  trimmed  ")
      expect(builder.documents.first[:text]).to eq("trimmed")
    end
  end

  describe "#<<" do
    subject(:builder) { described_class.new(index_name) }

    it "is alias for add" do
      builder << "Document"
      expect(builder.count).to eq(1)
    end
  end

  describe "#add_file" do
    subject(:builder) { described_class.new(index_name) }

    before do
      FileUtils.mkdir_p("spec/tmp")
      File.write("spec/tmp/test.txt", "File content here")
    end

    it "adds file content" do
      builder.add_file("spec/tmp/test.txt")
      expect(builder.documents.first[:text]).to eq("File content here")
    end

    it "adds file metadata" do
      builder.add_file("spec/tmp/test.txt")
      doc = builder.documents.first
      expect(doc[:metadata][:source]).to eq("spec/tmp/test.txt")
      expect(doc[:metadata][:filename]).to eq("test.txt")
      expect(doc[:metadata][:extension]).to eq(".txt")
    end

    it "merges custom metadata" do
      builder.add_file("spec/tmp/test.txt", category: "docs")
      expect(builder.documents.first[:metadata][:category]).to eq("docs")
    end

    it "raises if file not found" do
      expect do
        builder.add_file("nonexistent.txt")
      end.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#add_directory" do
    subject(:builder) { described_class.new(index_name) }

    before do
      FileUtils.mkdir_p("spec/tmp/docs")
      File.write("spec/tmp/docs/one.md", "First document")
      File.write("spec/tmp/docs/two.md", "Second document")
      File.write("spec/tmp/docs/three.txt", "Third document")
    end

    it "adds all files from directory" do
      builder.add_directory("spec/tmp/docs")
      expect(builder.count).to eq(3)
    end

    it "filters by extension" do
      builder.add_directory("spec/tmp/docs", extensions: [".md"])
      expect(builder.count).to eq(2)
    end

    it "raises if directory not found" do
      expect do
        builder.add_directory("nonexistent/")
      end.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#add_all" do
    subject(:builder) { described_class.new(index_name) }

    it "adds array of strings" do
      builder.add_all(%w[One Two Three])
      expect(builder.count).to eq(3)
    end

    it "adds array of hashes" do
      builder.add_all([
                        { text: "First", source: "a" },
                        { text: "Second", source: "b" }
                      ])
      expect(builder.count).to eq(2)
      expect(builder.documents.first[:metadata][:source]).to eq("a")
    end
  end

  describe "#count / #size" do
    subject(:builder) { described_class.new(index_name) }

    it "returns document count" do
      builder.add("One")
      builder.add("Two")
      expect(builder.count).to eq(2)
      expect(builder.size).to eq(2)
    end
  end

  describe "#empty?" do
    subject(:builder) { described_class.new(index_name) }

    it "returns true when no documents" do
      expect(builder).to be_empty
    end

    it "returns false when has documents" do
      builder.add("Doc")
      expect(builder).not_to be_empty
    end
  end

  describe "#save" do
    context "with leann backend (default)" do
      subject(:builder) { described_class.new(index_name) }

      before do
        allow(builder).to receive(:embedding_provider).and_return(mock_provider)
      end

      it "raises when empty" do
        expect { builder.save }.to raise_error(Leann::EmptyIndexError)
      end

      it "creates leann graph files" do
        builder.add("Test document one")
        builder.add("Test document two")
        builder.save

        expect(File.exist?("#{index_name}.leann.meta.json")).to be true
        expect(File.exist?("#{index_name}.leann.passages.jsonl")).to be true
        expect(File.exist?("#{index_name}.leann.graph.bin")).to be true
      end

      it "returns Index object" do
        builder.add("Test")
        result = builder.save

        expect(result).to be_a(Leann::Index)
        expect(result.name).to eq(index_name)
      end

      it "saves metadata with leann backend" do
        builder.add("Test")
        builder.save

        meta = JSON.parse(File.read("#{index_name}.leann.meta.json"))
        expect(meta["name"]).to eq(index_name)
        expect(meta["document_count"]).to eq(1)
        expect(meta["backend"]).to eq("leann")
      end
    end
  end
end

# frozen_string_literal: true

RSpec.describe Leann::Index do
  let(:index_name) { "test_index_#{Time.now.to_i}" }
  let(:index_path) { "#{index_name}.leann" }

  let(:sample_metadata) do
    {
      version: "1.0",
      name: index_name,
      backend: "leann",
      embedding_provider: "openai",
      embedding_model: "text-embedding-3-small",
      dimensions: 1536,
      document_count: 3,
      created_at: Time.now.utc.iso8601
    }
  end

  before do
    # Create sample index files
    File.write("#{index_path}.meta.json", JSON.generate(sample_metadata))

    File.open("#{index_path}.passages.jsonl", "w") do |f|
      f.puts JSON.generate({ id: "1", text: "First doc", metadata: { source: "a" } })
      f.puts JSON.generate({ id: "2", text: "Second doc", metadata: { source: "b" } })
      f.puts JSON.generate({ id: "3", text: "Third doc", metadata: { source: "c" } })
    end

    File.write("#{index_path}.passages.offsets", JSON.generate({ "1" => 0, "2" => 50, "3" => 100 }))
  end

  after do
    Dir.glob("#{index_name}*").each { |f| FileUtils.rm_rf(f) }
  end

  describe ".open" do
    it "opens existing index" do
      index = described_class.open(index_name)
      expect(index).to be_a(described_class)
      expect(index.name).to eq(index_name)
    end

    it "raises for non-existent index" do
      expect do
        described_class.open("nonexistent")
      end.to raise_error(Leann::IndexNotFoundError)
    end
  end

  describe ".exists?" do
    it "returns true for existing index" do
      expect(described_class.exists?(index_name)).to be true
    end

    it "returns false for non-existent index" do
      expect(described_class.exists?("nonexistent")).to be false
    end
  end

  describe ".list" do
    it "lists indexes in directory" do
      indexes = described_class.list(".")
      expect(indexes).to include(index_name)
    end
  end

  describe ".delete" do
    it "deletes index files" do
      expect(described_class.delete(index_name)).to be true
      expect(described_class.exists?(index_name)).to be false
    end

    it "returns false for non-existent index" do
      expect(described_class.delete("nonexistent")).to be false
    end
  end

  describe "#document_count" do
    subject(:index) { described_class.open(index_name) }

    it "returns document count from metadata" do
      expect(index.document_count).to eq(3)
    end
  end

  describe "#embedding_model" do
    subject(:index) { described_class.open(index_name) }

    it "returns embedding model" do
      expect(index.embedding_model).to eq("text-embedding-3-small")
    end
  end

  describe "#embedding_provider" do
    subject(:index) { described_class.open(index_name) }

    it "returns embedding provider as symbol" do
      expect(index.embedding_provider).to eq(:openai)
    end
  end

  describe "#dimensions" do
    subject(:index) { described_class.open(index_name) }

    it "returns dimensions" do
      expect(index.dimensions).to eq(1536)
    end
  end

  describe "#backend" do
    subject(:index) { described_class.open(index_name) }

    it "returns backend as symbol" do
      expect(index.backend).to eq(:leann)
    end
  end

  describe "#created_at" do
    subject(:index) { described_class.open(index_name) }

    it "returns Time object" do
      expect(index.created_at).to be_a(Time)
    end
  end

  describe "#to_s" do
    subject(:index) { described_class.open(index_name) }

    it "includes key information" do
      str = index.to_s
      expect(str).to include(index_name)
      expect(str).to include("Documents: 3")
      expect(str).to include("text-embedding-3-small")
    end
  end

  describe "#inspect" do
    subject(:index) { described_class.open(index_name) }

    it "shows class and attributes" do
      expect(index.inspect).to include("Leann::Index")
      expect(index.inspect).to include(index_name)
    end
  end

  describe "#each_passage" do
    subject(:index) { described_class.open(index_name) }

    it "iterates over passages" do
      texts = []
      index.each_passage { |p| texts << p[:text] }
      expect(texts).to eq(["First doc", "Second doc", "Third doc"])
    end

    it "returns enumerator without block" do
      enum = index.each_passage
      expect(enum).to be_an(Enumerator)
      expect(enum.to_a.size).to eq(3)
    end
  end

  describe "#get_passage" do
    subject(:index) { described_class.open(index_name) }

    it "returns passage by id" do
      passage = index.get_passage("2")
      expect(passage[:text]).to eq("Second doc")
    end

    it "returns nil for unknown id" do
      expect(index.get_passage("unknown")).to be_nil
    end
  end
end

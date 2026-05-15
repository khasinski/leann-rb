# frozen_string_literal: true

# This file tests Leann::Rails module - requires builder_spec.rb to be loaded first
# for the ActiveRecord mock

require_relative "builder_spec"

RSpec.describe Leann::Rails do
  let(:index_name) { "test_rails_#{Time.now.to_i}" }

  let(:mock_provider) do
    double("EmbeddingProvider").tap do |provider|
      allow(provider).to receive(:compute) do |texts|
        texts.map { Array.new(384) { rand(-1.0..1.0) } }
      end
    end
  end

  before do
    Leann.configure do |config|
      config.openai_api_key = "test-key"
    end

    Leann::Rails::Index.clear_records!
    Leann::Rails::Passage.clear_records!
  end

  describe ".build" do
    it "builds an index with DSL" do
      builder = Leann::Rails::Builder.new(index_name)
      allow(builder).to receive(:embedding_provider).and_return(mock_provider)
      allow(Leann::Rails::Builder).to receive(:new).and_return(builder)

      index = described_class.build(index_name) do
        add "First document"
        add "Second document"
      end

      expect(index).to be_a(Leann::Rails::Index)
      expect(index.name).to eq(index_name)
    end
  end

  describe ".exists?" do
    it "returns false when index does not exist" do
      expect(described_class.exists?("nonexistent")).to be false
    end

    it "returns true when index exists" do
      Leann::Rails::Index.create!(
        name: index_name,
        embedding_provider: "openai",
        embedding_model: "text-embedding-3-small",
        dimensions: 1536
      )

      expect(described_class.exists?(index_name)).to be true
    end
  end

  describe ".list" do
    it "returns list of index names" do
      Leann::Rails::Index.create!(name: "index_a", embedding_provider: "openai", dimensions: 1536)
      Leann::Rails::Index.create!(name: "index_b", embedding_provider: "openai", dimensions: 1536)

      expect(described_class.list).to eq(%w[index_a index_b])
    end
  end

  describe ".delete" do
    it "deletes existing index" do
      Leann::Rails::Index.create!(
        name: index_name,
        embedding_provider: "openai",
        dimensions: 1536
      )

      expect(described_class.delete(index_name)).to be true
      expect(described_class.exists?(index_name)).to be false
    end

    it "returns false for non-existent index" do
      expect(described_class.delete("nonexistent")).to be false
    end
  end
end

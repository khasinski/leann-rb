# frozen_string_literal: true

# Mock ActiveRecord for testing without Rails
module ActiveRecord
  class Base
    class << self
      attr_accessor :table_name, :_attributes

      def has_many(*); end
      def belongs_to(*); end
      def validates(*); end
      def serialize(*); end

      def attribute_accessors(*attrs)
        @_attributes = attrs
        attr_accessor(*attrs)
      end

      def find_by(conditions)
        @records&.find { |r| conditions.all? { |k, v| r.instance_variable_get("@#{k}") == v } }
      end

      def find_by!(conditions)
        find_by(conditions) || raise("Record not found")
      end

      def exists?(conditions)
        !!find_by(conditions)
      end

      def create!(attrs)
        record = new
        attrs.each { |k, v| record.instance_variable_set("@#{k}", v) }
        record.instance_variable_set("@id", (@records&.size || 0) + 1)
        record.instance_variable_set("@created_at", Time.now)
        record.instance_variable_set("@updated_at", Time.now)
        @records ||= []
        @records << record
        record
      end

      def pluck(*columns)
        @records&.map { |r| columns.size == 1 ? r.instance_variable_get("@#{columns[0]}") : columns.map { |c| r.instance_variable_get("@#{c}") } } || []
      end

      def insert_all(records)
        records.each { |r| create!(r) }
      end

      def clear_records!
        @records = []
      end

      def index_by(attr)
        (@records || []).each_with_object({}) { |r, h| h[r.instance_variable_get("@#{attr}")] = r }
      end

      def count
        @records&.size || 0
      end
    end

    attr_accessor :id, :created_at, :updated_at

    def initialize(attrs = {})
      attrs.each { |k, v| instance_variable_set("@#{k}", v) }
    end

    def update!(attrs)
      attrs.each { |k, v| instance_variable_set("@#{k}", v) }
      @updated_at = Time.now
      self
    end

    def destroy
      self.class.instance_variable_get(:@records)&.delete(self)
      true
    end
  end
end

# Add Time.current method for Rails compatibility
class << Time
  def current
    now
  end
end unless Time.respond_to?(:current)

# Now require Rails integration
require_relative "../../../lib/leann/rails"

# Add attribute accessors to models
module Leann
  module Rails
    class Index < ::ActiveRecord::Base
      attr_accessor :name, :embedding_provider, :embedding_model, :dimensions, :config

      def passages
        Passage.instance_variable_get(:@records)&.select { |p| p.instance_variable_get(:@leann_index_id) == id } || []
      end

      def embedding_provider_sym
        embedding_provider&.to_sym
      end
    end

    class Passage < ::ActiveRecord::Base
      attr_accessor :leann_index_id, :external_id, :text, :metadata, :neighbors

      def metadata_sym
        (metadata || {}).transform_keys(&:to_sym)
      end

      def neighbor_ids
        neighbors || []
      end
    end
  end
end

RSpec.describe Leann::Rails::Builder do
  let(:index_name) { "test_rails_builder_#{Time.now.to_i}" }

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

    # Clear mock records
    Leann::Rails::Index.clear_records!
    Leann::Rails::Passage.clear_records!
  end

  describe "#initialize" do
    it "sets index name" do
      builder = described_class.new(index_name)
      expect(builder.name).to eq(index_name)
    end

    it "defaults embedding provider based on configuration" do
      builder = described_class.new(index_name)
      expected = Leann.configuration.ruby_llm_available? ? :ruby_llm : :openai
      expect(builder.instance_variable_get(:@embedding_provider)).to eq(expected)
    end

    it "allows custom embedding provider" do
      builder = described_class.new(index_name, embedding: :ollama)
      expect(builder.instance_variable_get(:@embedding_provider)).to eq(:ollama)
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

    it "raises on nil text" do
      expect { builder.add(nil) }.to raise_error(ArgumentError, /nil/)
    end

    it "raises on empty text" do
      expect { builder.add("   ") }.to raise_error(ArgumentError, /empty/)
    end
  end

  describe "#save" do
    subject(:builder) { described_class.new(index_name) }

    before do
      allow(builder).to receive(:embedding_provider).and_return(mock_provider)
    end

    it "raises when empty" do
      expect { builder.save }.to raise_error(Leann::EmptyIndexError)
    end

    it "creates index record" do
      builder.add("Test document one")
      builder.add("Test document two")

      index = builder.save

      expect(index).to be_a(Leann::Rails::Index)
      expect(index.name).to eq(index_name)
      expect(index.dimensions).to eq(384)
    end

    it "stores passages in database" do
      builder.add("First doc", category: "test")
      builder.add("Second doc", category: "test")

      index = builder.save
      passages = index.passages

      expect(passages.map { |p| p.text }).to include("First doc", "Second doc")
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
end

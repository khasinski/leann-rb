# frozen_string_literal: true

RSpec.describe Leann::Embedding::Base do
  describe "#initialize" do
    it "sets model name" do
      provider = described_class.new(model: "test-model")
      expect(provider.model).to eq("test-model")
    end

    it "sets dimensions to nil" do
      provider = described_class.new(model: "test")
      expect(provider.dimensions).to be_nil
    end
  end

  describe "#compute" do
    it "raises NotImplementedError" do
      provider = described_class.new(model: "test")
      expect do
        provider.compute(["text"])
      end.to raise_error(NotImplementedError, /must implement/)
    end
  end

  describe "#compute_one" do
    it "calls compute and returns first result" do
      provider = described_class.new(model: "test")
      allow(provider).to receive(:compute).with(["text"]).and_return([[1.0, 2.0, 3.0]])

      result = provider.compute_one("text")
      expect(result).to eq([1.0, 2.0, 3.0])
    end
  end

  describe "#normalize (protected)" do
    let(:provider) { described_class.new(model: "test") }

    it "normalizes vector to unit length" do
      embedding = [3.0, 4.0] # 3-4-5 triangle
      normalized = provider.send(:normalize, embedding)

      expect(normalized).to eq([0.6, 0.8])
    end

    it "handles zero vector" do
      embedding = [0.0, 0.0, 0.0]
      normalized = provider.send(:normalize, embedding)

      expect(normalized).to eq([0.0, 0.0, 0.0])
    end

    it "returns unit norm" do
      embedding = [1.0, 2.0, 3.0, 4.0, 5.0]
      normalized = provider.send(:normalize, embedding)

      norm = Math.sqrt(normalized.sum { |x| x * x })
      expect(norm).to be_within(0.0001).of(1.0)
    end
  end

  describe "#in_batches (protected)" do
    let(:provider) { described_class.new(model: "test") }

    it "yields items in batches" do
      items = (1..10).to_a
      batches = []

      provider.send(:in_batches, items, 3) do |batch|
        batches << batch
      end

      expect(batches).to eq([
                              [1, 2, 3],
                              [4, 5, 6],
                              [7, 8, 9],
                              [10]
                            ])
    end

    it "handles empty array" do
      batches = []
      provider.send(:in_batches, [], 3) { |b| batches << b }
      expect(batches).to be_empty
    end

    it "handles batch size larger than items" do
      batches = []
      provider.send(:in_batches, [1, 2], 10) { |b| batches << b }
      expect(batches).to eq([[1, 2]])
    end
  end
end

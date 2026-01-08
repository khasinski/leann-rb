# frozen_string_literal: true

require_relative "../../../lib/leann/backend/base"

RSpec.describe Leann::Backend::Base do
  describe "#initialize" do
    it "sets dimensions" do
      backend = described_class.new(dimensions: 1536)
      expect(backend.dimensions).to eq(1536)
    end
  end

  describe "#build" do
    it "raises NotImplementedError" do
      backend = described_class.new(dimensions: 1536)
      expect {
        backend.build([], [], "test")
      }.to raise_error(NotImplementedError, /Subclasses must implement #build/)
    end
  end

  describe "#search" do
    it "raises NotImplementedError" do
      backend = described_class.new(dimensions: 1536)
      expect {
        backend.search([0.1, 0.2], limit: 5)
      }.to raise_error(NotImplementedError, /Subclasses must implement #search/)
    end
  end

  describe ".load" do
    it "raises NotImplementedError" do
      expect {
        described_class.load("test")
      }.to raise_error(NotImplementedError, /Subclasses must implement .load/)
    end
  end
end

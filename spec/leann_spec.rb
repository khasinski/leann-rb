# frozen_string_literal: true

RSpec.describe Leann do
  it "has a version number" do
    expect(Leann::VERSION).not_to be_nil
    expect(Leann::VERSION).to match(/\d+\.\d+\.\d+/)
  end

  describe ".configuration" do
    it "returns Configuration instance" do
      expect(Leann.configuration).to be_a(Leann::Configuration)
    end
  end

  describe ".configure" do
    it "yields configuration" do
      Leann.configure do |config|
        expect(config).to be_a(Leann::Configuration)
      end
    end
  end
end

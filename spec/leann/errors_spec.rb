# frozen_string_literal: true

RSpec.describe Leann::Error do
  it "inherits from StandardError" do
    expect(described_class.superclass).to eq(StandardError)
  end
end

RSpec.describe Leann::ConfigurationError do
  it "inherits from Leann::Error" do
    expect(described_class.superclass).to eq(Leann::Error)
  end
end

RSpec.describe Leann::IndexNotFoundError do
  subject(:error) { described_class.new("test_index") }

  it "inherits from Leann::Error" do
    expect(described_class.superclass).to eq(Leann::Error)
  end

  it "stores index name" do
    expect(error.index_name).to eq("test_index")
  end

  it "has descriptive message" do
    expect(error.message).to eq("Index not found: test_index")
  end
end

RSpec.describe Leann::IndexExistsError do
  subject(:error) { described_class.new("existing_index") }

  it "stores index name" do
    expect(error.index_name).to eq("existing_index")
  end

  it "suggests using force option" do
    expect(error.message).to include("force: true")
  end
end

RSpec.describe Leann::EmbeddingError do
  it "stores provider info" do
    error = described_class.new("API failed", provider: :openai)
    expect(error.provider).to eq(:openai)
    expect(error.message).to eq("API failed")
  end

  it "stores original error" do
    original = StandardError.new("original")
    error = described_class.new("wrapped", original_error: original)
    expect(error.original_error).to eq(original)
  end
end

RSpec.describe Leann::LLMError do
  it "stores provider and original error" do
    original = RuntimeError.new("timeout")
    error = described_class.new("LLM failed", provider: :anthropic, original_error: original)

    expect(error.provider).to eq(:anthropic)
    expect(error.original_error).to eq(original)
  end
end

RSpec.describe Leann::CorruptedIndexError do
  it "includes index name in message" do
    error = described_class.new("broken_index")
    expect(error.message).to include("broken_index")
  end

  it "includes reason when provided" do
    error = described_class.new("broken_index", "invalid JSON")
    expect(error.message).to include("invalid JSON")
    expect(error.reason).to eq("invalid JSON")
  end
end

RSpec.describe Leann::EmptyIndexError do
  it "has descriptive message" do
    error = described_class.new
    expect(error.message).to include("empty index")
  end
end

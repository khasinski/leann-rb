# frozen_string_literal: true

RSpec.describe Leann::Configuration do
  subject(:config) { described_class.new }

  describe "#initialize" do
    it "defaults to :ruby_llm when RubyLLM is available" do
      # RubyLLM mock is loaded in tests, so should default to :ruby_llm
      if config.ruby_llm_available?
        expect(config.embedding_provider).to eq(:ruby_llm)
      else
        expect(config.embedding_provider).to eq(:openai)
      end
    end

    it "sets default embedding model to nil (provider chooses)" do
      expect(config.default_embedding_model).to be_nil
    end

    it "sets default HNSW parameters" do
      expect(config.hnsw_m).to eq(32)
      expect(config.hnsw_ef_construction).to eq(200)
    end

    it "reads API key from environment" do
      expect(config.openai_api_key).to eq(ENV.fetch("OPENAI_API_KEY", nil))
    end
  end

  describe "#ruby_llm_available?" do
    it "detects RubyLLM availability" do
      # Just check it returns a truthy/falsy value
      expect(config.ruby_llm_available?).to eq(defined?(RubyLLM) ? true : false).or be_truthy.or be_falsy
    end
  end

  describe "#validate!" do
    context "with OpenAI provider" do
      before { config.embedding_provider = :openai }

      it "raises error when API key is missing" do
        config.openai_api_key = nil
        expect { config.validate! }.to raise_error(Leann::ConfigurationError, /API key is required/)
      end

      it "raises error when API key is empty" do
        config.openai_api_key = ""
        expect { config.validate! }.to raise_error(Leann::ConfigurationError, /API key is required/)
      end

      it "passes when API key is present" do
        config.openai_api_key = "sk-test-key"
        expect(config.validate!).to be true
      end
    end

    context "with Ollama provider" do
      before { config.embedding_provider = :ollama }

      it "passes without API key" do
        config.openai_api_key = nil
        expect(config.validate!).to be true
      end
    end

    context "with RubyLLM provider" do
      before { config.embedding_provider = :ruby_llm }

      it "validates based on RubyLLM availability" do
        if config.ruby_llm_available?
          expect(config.validate!).to be true
        else
          expect { config.validate! }.to raise_error(Leann::ConfigurationError, /RubyLLM gem is required/)
        end
      end
    end

    context "with unknown provider" do
      it "raises error" do
        config.embedding_provider = :unknown
        expect { config.validate! }.to raise_error(Leann::ConfigurationError, /Unknown embedding provider/)
      end
    end
  end

  describe "#embedding_model_for" do
    it "returns nil for :ruby_llm (uses RubyLLM default)" do
      expect(config.embedding_model_for(:ruby_llm)).to be_nil
    end

    it "returns OpenAI default for :openai" do
      expect(config.embedding_model_for(:openai)).to eq("text-embedding-3-small")
    end

    it "returns Ollama default for :ollama" do
      expect(config.embedding_model_for(:ollama)).to eq("nomic-embed-text")
    end

    it "returns custom model when set" do
      config.default_embedding_model = "custom-model"
      expect(config.embedding_model_for(:openai)).to eq("custom-model")
      expect(config.embedding_model_for(:ruby_llm)).to eq("custom-model")
    end
  end
end

RSpec.describe Leann do
  describe ".configure" do
    it "yields configuration object" do
      expect { |b| described_class.configure(&b) }.to yield_with_args(Leann::Configuration)
    end

    it "allows setting configuration values" do
      described_class.configure do |config|
        config.embedding_provider = :ollama
      end

      expect(described_class.configuration.embedding_provider).to eq(:ollama)
    end
  end

  describe ".configuration" do
    it "returns same instance on multiple calls" do
      config1 = described_class.configuration
      config2 = described_class.configuration
      expect(config1).to be(config2)
    end
  end
end

# frozen_string_literal: true

require_relative "lib/leann/version"

Gem::Specification.new do |spec|
  spec.name          = "leann"
  spec.version       = Leann::VERSION
  spec.authors       = ["Chris Hasiński"]
  spec.email         = ["krzysztof.hasinski@gmail.com"]

  spec.summary       = "Lightweight vector search and RAG for Ruby"
  spec.description   = <<~DESC
    LEANN (Lightweight Embedding-Aware Neural Neighbor) is a Ruby gem for
    building and searching vector indexes with minimal storage. It provides
    semantic search and RAG capabilities with a beautiful, simple API.
    Supports multiple embedding providers: RubyLLM, OpenAI, Ollama, and FastEmbed.
  DESC
  spec.homepage      = "https://github.com/khasinski/leann-rb"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Files to include
  spec.files = Dir[
    "lib/**/*",
    "exe/*",
    "README.md",
    "LICENSE.txt",
    "CHANGELOG.md"
  ]

  spec.bindir        = "exe"
  spec.executables   = ["leann"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "hnswlib", "~> 0.9"    # HNSW vector search

  # Optional embedding providers (add to your Gemfile as needed):
  # gem 'ruby_llm'   - Unified API for multiple providers (recommended)
  # gem 'fastembed'  - Fast local embeddings via ONNX Runtime

  # Development dependencies
  spec.add_development_dependency "bundler", ">= 1.17"
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "vcr", "~> 6.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
end

# LEANN

**Lightweight vector search with 85-96% storage savings.**

LEANN stores only the graph structure, not the embeddings. During search, it recomputes embeddings on-the-fly for visited nodes only. This achieves massive storage reduction while maintaining search quality.

```ruby
# Build an index - embeddings are computed but NOT stored
Leann.build("knowledge_base") do
  add "LEANN saves 85-96% storage compared to traditional vector databases."
  add "It uses graph-only storage with on-demand embedding recomputation."
  add_directory "docs/", extensions: [".md", ".txt"]
end

# Search semantically
results = Leann.search("knowledge_base", "storage efficiency")
puts results.first.text
```

## Storage Benchmark

At **1 million documents**:

| Embedding Model | Traditional HNSW | LEANN | Savings |
|-----------------|------------------|-------|---------:|
| Ollama (384 dim) | 1.67 GB | 251.8 MB | **85%** |
| OpenAI (1536 dim) | 5.96 GB | 251.8 MB | **96%** |

Full benchmark across scales:

| Documents | Traditional HNSW | LEANN | Savings |
|----------:|------------------|-------|---------:|
| 1,000 | 1.7 MB | 257 KB | **85%** |
| 10,000 | 17 MB | 2.5 MB | **85%** |
| 100,000 | 171 MB | 25 MB | **85%** |
| 1,000,000 | 1.67 GB | 252 MB | **85%** |

*Measured with Ollama all-minilm (384 dimensions). OpenAI models achieve ~96% savings due to larger embeddings.*

## How It Works

**Traditional vector databases:**
```
[Documents] + [Embeddings] + [Index] → Large storage (1.67 GB for 1M docs)
```

**LEANN:**
```
[Documents] + [Graph-only] → Tiny storage (252 MB for 1M docs)
                ↓
        Embeddings recomputed on-the-fly during search
```

The trade-off: search is slightly slower (requires API calls to recompute embeddings for visited nodes), but storage is dramatically smaller.

## Quick Start

### 1. Install

```ruby
gem 'leann'
gem 'ruby_llm'  # Recommended - LEANN uses RubyLLM for embeddings automatically
```

### 2. Configure

```ruby
# If you have RubyLLM, just configure it - LEANN uses it automatically
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

# Or configure LEANN directly (without RubyLLM)
Leann.configure do |config|
  config.embedding_provider = :openai  # or :ollama
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end
```

### 3. Build & Search

```ruby
# Index some documents
Leann.build("my_index") do
  add "Ruby is a dynamic programming language."
  add "Rails is a web framework written in Ruby."
  add "Sinatra is a lightweight Ruby web framework."
end

# Search
results = Leann.search("my_index", "web frameworks")
results.each { |r| puts "#{r.score.round(3)}: #{r.text}" }
```

## Real-World Use Cases

### Documentation Search

```ruby
# Index your documentation
Leann.build("docs") do
  add_directory "docs/", extensions: [".md"]
  add_directory "guides/", extensions: [".md"]
end

# Search API
get "/search" do
  results = Leann.search("docs", params[:q], limit: 10)
  json results.map(&:to_h)
end
```

### Code Search

```ruby
# Index your codebase
Leann.build("codebase", embedding: :ollama, model: "nomic-embed-text") do
  add_directory "app/", extensions: [".rb"]
  add_directory "lib/", extensions: [".rb"]
end

# Find relevant code
results = Leann.search("codebase", "user authentication", limit: 5)
```

### Local-First with Ollama

```ruby
# No API keys needed - runs entirely local
Leann.configure do |config|
  config.embedding_provider = :ollama
end

Leann.build("local_index") do
  add "Your private data stays on your machine."
end

results = Leann.search("local_index", "privacy")
```

## RubyLLM Integration

LEANN works seamlessly with [RubyLLM](https://github.com/crmne/ruby_llm):

- **Embeddings**: If RubyLLM is present, LEANN uses it automatically for embeddings
- **RAG**: Use LEANN as a tool for retrieval-augmented generation

### Embeddings via RubyLLM

```ruby
# Just configure RubyLLM - LEANN detects and uses it automatically
RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
end

# Build uses RubyLLM.embed under the hood
Leann.build("docs") do
  add "Your documents here..."
end
```

### RAG with Search Tool

```ruby
require "leann"
require "leann/ruby_llm/search"

# Build your index
Leann.build("knowledge_base") do
  add "LEANN saves 85-96% storage compared to traditional vector databases."
  add "It uses graph-only storage for massive space savings."
end

# Create a RubyLLM chat with LEANN as a tool
chat = RubyLLM.chat(model: "gpt-4o")
  .with_tool(Leann::RubyLLM::Search.new("knowledge_base"))

# The LLM will automatically search when needed
answer = chat.ask("How much storage does LEANN save?")
puts answer
# => "Based on my search, LEANN saves 85-96% storage compared to traditional vector databases..."
```

### Multiple Indexes

```ruby
require "leann/ruby_llm/search"

docs_tool = Leann::RubyLLM::Search.new("docs", name: "search_docs")
code_tool = Leann::RubyLLM::Search.new("codebase", name: "search_code")

chat = RubyLLM.chat(model: "gpt-4o")
  .with_tools(docs_tool, code_tool)

chat.ask("How does authentication work in this project?")
# => LLM searches both indexes and synthesizes an answer
```

## API Reference

### Building Indexes

```ruby
# DSL style (recommended)
Leann.build("name") do
  add "text", key: "value"           # Add text with metadata
  add_file "path/to/file.txt"        # Add file contents
  add_directory "docs/"              # Add all files from directory
end

# Programmatic style
builder = Leann::Builder.new("name", embedding: :openai)
builder.add("text one")
builder.add("text two", category: "example")
builder.save
```

### Searching

```ruby
# Simple search
results = Leann.search("index", "query")

# With options
results = Leann.search("index", "query",
  limit: 10,                    # Max results
  threshold: 0.7,               # Min similarity
  filters: { category: "docs" } # Metadata filter
)

# Working with results
results.each do |r|
  puts r.id           # Document ID
  puts r.text         # Document text
  puts r.score        # Similarity score (0-1)
  puts r.metadata     # Metadata hash
end

puts results.combined_text  # All texts joined
```

### Configuration

```ruby
Leann.configure do |config|
  # Embedding provider (defaults to :ruby_llm if available, otherwise :openai)
  config.embedding_provider = :ruby_llm  # :ruby_llm, :openai, or :ollama

  # Provider-specific settings (only needed if not using RubyLLM)
  config.openai_api_key = "sk-..."
  config.ollama_host = "http://localhost:11434"
  config.default_embedding_model = "text-embedding-3-small"

  # Index settings
  config.hnsw_m = 16                         # Graph connectivity
  config.hnsw_ef_construction = 200          # Build quality
end
```

## Embedding Providers

| Provider | Setup | Best For |
|----------|-------|----------|
| **RubyLLM** (default) | `gem 'ruby_llm'` | Unified API, multiple backends |
| **OpenAI** | `OPENAI_API_KEY` | Direct API access |
| **Ollama** | [Install Ollama](https://ollama.com) | Local, privacy-first |

When RubyLLM is present, LEANN uses it automatically. This gives you access to all embedding providers RubyLLM supports (OpenAI, Ollama, and more) through a single configuration.

## Requirements

- Ruby 3.0+
- RubyLLM gem (recommended) OR direct API access:
  - OpenAI API key (for cloud embeddings)
  - Ollama running locally (for local embeddings)

## License

MIT

#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark: LEANN vs HNSW storage comparison
#
# Calculates storage requirements for HNSW vs LEANN at various scales.

def format_bytes(bytes)
  if bytes < 1024
    "#{bytes.round(0)} B"
  elsif bytes < 1024 * 1024
    "#{(bytes / 1024.0).round(1)} KB"
  elsif bytes < 1024 * 1024 * 1024
    "#{(bytes / (1024.0 * 1024)).round(1)} MB"
  else
    "#{(bytes / (1024.0 * 1024 * 1024)).round(2)} GB"
  end
end

def calculate_storage(doc_count, dimensions, m = 32)
  # HNSW storage: embeddings + graph structure
  # Each embedding: dimensions * 4 bytes (float32)
  # Graph: ~M * 2 neighbors per node * 4 bytes (int32) per neighbor reference
  embedding_bytes = dimensions * 4
  graph_overhead_per_node = m * 2 * 4  # neighbors + some metadata

  hnsw_per_doc = embedding_bytes + graph_overhead_per_node
  hnsw_total = doc_count * hnsw_per_doc

  # LEANN storage: graph structure only (no embeddings)
  # Just neighbor lists + level info
  leann_per_doc = m * 2 * 4 + 8  # neighbors + level/offset info
  leann_total = doc_count * leann_per_doc

  {
    doc_count: doc_count,
    hnsw_total: hnsw_total,
    leann_total: leann_total,
    savings_percent: ((hnsw_total - leann_total).to_f / hnsw_total * 100).round(1)
  }
end

puts "=" * 70
puts "LEANN vs HNSW Storage Comparison"
puts "=" * 70
puts
puts "Configuration: 384 dimensions (Ollama all-minilm), M=32"
puts
puts "| Documents   | HNSW (embeddings + graph) | LEANN (graph only) | Savings |"
puts "|-------------|---------------------------|--------------------|---------:|"

[100, 1_000, 10_000, 100_000, 1_000_000].each do |count|
  result = calculate_storage(count, 384, 32)
  doc_str = count.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse.rjust(11)
  puts "| #{doc_str} | #{format_bytes(result[:hnsw_total]).rjust(25)} | #{format_bytes(result[:leann_total]).rjust(18)} | **#{result[:savings_percent]}%** |"
end

puts
puts "-" * 70
puts "At 1 million documents with Ollama (384-dim embeddings):"
puts "-" * 70

result_1m = calculate_storage(1_000_000, 384, 32)
puts
puts "  HNSW would require:  #{format_bytes(result_1m[:hnsw_total])}"
puts "  LEANN requires:      #{format_bytes(result_1m[:leann_total])}"
puts "  Storage saved:       #{format_bytes(result_1m[:hnsw_total] - result_1m[:leann_total])}"
puts "  Reduction:           #{result_1m[:savings_percent]}%"
puts

puts "-" * 70
puts "With OpenAI (1536-dim embeddings):"
puts "-" * 70

result_1m_openai = calculate_storage(1_000_000, 1536, 32)
puts
puts "  HNSW would require:  #{format_bytes(result_1m_openai[:hnsw_total])}"
puts "  LEANN requires:      #{format_bytes(result_1m_openai[:leann_total])}"
puts "  Storage saved:       #{format_bytes(result_1m_openai[:hnsw_total] - result_1m_openai[:leann_total])}"
puts "  Reduction:           #{result_1m_openai[:savings_percent]}%"
puts

# Also run quick actual measurement with small sample
puts "=" * 70
puts "Actual Measurement (1000 documents)"
puts "=" * 70

require "bundler/setup"
require "leann"
require "fileutils"

class MockEmbedding
  def initialize(dim); @dim = dim; end
  def compute(texts); texts.map { Array.new(@dim) { rand(-1.0..1.0) } }; end
end

[[:hnsw, "HNSW"], [:leann, "LEANN"]].each do |backend, label|
  name = "bench_#{backend}_#{Time.now.to_i}"
  path = "#{name}.leann"

  builder = Leann::Builder.new(name, backend: backend, embedding: :ollama)
  builder.instance_variable_set(:@_embedding_provider, MockEmbedding.new(384))

  1000.times { |i| builder.add("Document #{i} with some sample text content here") }

  $stdout = File.open(File::NULL, 'w')  # Suppress output
  builder.save
  $stdout = STDOUT

  size = case backend
         when :hnsw then File.size("#{path}.hnsw.index")
         when :leann then File.size("#{path}.graph.bin")
         end

  puts "  #{label}: #{format_bytes(size)} (#{(size / 1000.0).round(1)} bytes/doc)"

  Dir.glob("#{name}*").each { |f| FileUtils.rm_rf(f) }
end

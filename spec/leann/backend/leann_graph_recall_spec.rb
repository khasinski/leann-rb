# frozen_string_literal: true

require_relative "../../../lib/leann/embedding/base"
require_relative "../../../lib/leann/backend/leann_graph"

RSpec.describe Leann::Backend::LeannGraph, "recall@k" do
  # Deterministic synthetic dataset: each document is a fixed-length random vector.
  # We compare the graph's top-k against the brute-force exact answer and require
  # that recall stays above a sensible threshold. This is a sanity check, not a
  # benchmark - SIFT-1K / GIST should live in benchmark/ rather than the spec suite.

  def build_corpus(seed:, count:, dimensions:)
    rng = Random.new(seed)
    Array.new(count) { Array.new(dimensions) { rng.rand(-1.0..1.0) } }
  end

  def cosine_distance(a, b)
    dot = 0.0
    na = 0.0
    nb = 0.0
    a.each_with_index do |v, i|
      dot += v * b[i]
      na += v * v
      nb += b[i] * b[i]
    end
    return 1.0 if na.zero? || nb.zero?

    1.0 - (dot / (Math.sqrt(na) * Math.sqrt(nb)))
  end

  def brute_force_topk(query, embeddings, k)
    embeddings
      .each_with_index
      .map { |emb, idx| [idx, cosine_distance(query, emb)] }
      .sort_by { |_, d| d }
      .first(k)
      .map(&:first)
  end

  # In-process embedding provider: looks up a precomputed vector by document ID.
  let(:in_memory_provider) do
    Class.new do
      def initialize(map)
        @map = map
      end

      def compute_one(text)
        @map.fetch(text)
      end

      def compute(texts)
        Array(texts).map { |t| @map.fetch(t) }
      end
    end
  end

  it "achieves >= 0.85 recall@10 on a 200-document corpus of 64-dim vectors" do
    dims = 64
    count = 200
    k = 10
    queries = 25

    embeddings = build_corpus(seed: 1, count: count, dimensions: dims)
    ids = embeddings.each_index.map { |i| "doc-#{i}" }
    passages = ids.zip(embeddings).to_h
    provider = in_memory_provider.new(passages.transform_keys { |k_| k_ })

    graph = described_class.new(dimensions: dims, m: 16, ef_construction: 100)
    graph.build(ids, embeddings)

    query_corpus = build_corpus(seed: 2, count: queries, dimensions: dims)

    recalls = query_corpus.map do |query|
      expected_idx = brute_force_topk(query, embeddings, k)
      expected_ids = expected_idx.map { |i| ids[i] }

      graph_results = graph.search(
        query,
        embedding_provider: provider,
        passages: ids.zip(ids).to_h, # map id -> id; provider looks up by "text" which is the id here
        limit: k,
        ef: 64
      )
      graph_ids = graph_results.map(&:first)

      (graph_ids & expected_ids).size.to_f / k
    end

    mean_recall = recalls.sum / recalls.size
    expect(mean_recall).to be >= 0.85,
                           "mean recall@#{k} was #{mean_recall.round(3)}, expected >= 0.85"
  end
end

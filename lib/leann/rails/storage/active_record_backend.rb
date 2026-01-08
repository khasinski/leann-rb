# frozen_string_literal: true

module Leann
  module Rails
    # ActiveRecord-based storage backend for LEANN graphs
    #
    # Stores graph structure (neighbor lists) in the passages table,
    # avoiding the need for separate binary files.
    #
    class ActiveRecordBackend
      attr_reader :index, :dimensions, :m, :ef_construction

      # @param index [Leann::Rails::Index] The index record
      def initialize(index)
        @index = index
        @dimensions = index.dimensions
        config = index.config || {}
        @m = config["hnsw_m"] || Leann.configuration.hnsw_m
        @ef_construction = config["hnsw_ef_construction"] || Leann.configuration.hnsw_ef_construction
        @entry_point_id = nil
        @max_level = 0
      end

      # Build the graph from documents and embeddings
      #
      # @param documents [Array<Hash>] Documents with :id, :text, :metadata
      # @param embeddings [Array<Array<Float>>] Embedding vectors
      def build(documents, embeddings)
        return if documents.empty?

        puts "Building LEANN graph with #{documents.size} nodes (M=#{@m})..."

        # Build in-memory graph first using the core algorithm
        graph = build_graph(documents, embeddings)

        # Store passages with neighbor information
        store_passages(documents, graph)

        # Store graph metadata in the index
        update_index_metadata(graph)

        puts "Graph built and stored in database: #{documents.size} passages"
      end

      # Search the graph
      #
      # @param query_embedding [Array<Float>] Query vector
      # @param embedding_provider [Leann::Embedding::Base] Provider for recomputing embeddings
      # @param passages [Hash] Passage texts by ID (for embedding recomputation)
      # @param limit [Integer] Number of results
      # @return [Array<Array>] Array of [id, score] pairs
      def search(query_embedding, embedding_provider:, passages:, limit:)
        return [] if @index.passages.empty?

        # Load graph metadata
        config = @index.config || {}
        entry_point_id = config["entry_point_id"]
        max_level = config["max_level"] || 0

        return [] unless entry_point_id

        # Perform HNSW search with on-the-fly embedding recomputation
        ef_search = [limit * 2, 50].max
        search_hnsw(query_embedding, entry_point_id, max_level, ef_search, embedding_provider, passages, limit)
      end

      private

      def build_graph(documents, embeddings)
        # Simple HNSW-like graph construction
        graph = {}
        levels = {}
        entry_point = nil
        max_level = 0

        documents.each_with_index do |doc, idx|
          id = doc[:id]
          embedding = embeddings[idx]
          level = random_level

          graph[id] = { embedding: embedding, neighbors: Array.new(level + 1) { [] } }
          levels[id] = level

          if entry_point.nil?
            entry_point = id
            max_level = level
          else
            # Insert into graph
            insert_node(graph, id, embedding, entry_point, max_level, level)

            if level > max_level
              max_level = level
              entry_point = id
            end
          end
        end

        { graph: graph, entry_point: entry_point, max_level: max_level }
      end

      def random_level
        level = 0
        ml = 1.0 / Math.log(@m)
        while rand < Math.exp(-level / ml) && level < 16
          level += 1
        end
        level
      end

      def insert_node(graph, new_id, new_embedding, entry_point, max_level, node_level)
        current = entry_point

        # Traverse from top to node's level
        (max_level).downto(node_level + 1) do |level|
          current = greedy_search_level(graph, new_embedding, current, level)
        end

        # Insert at each level
        node_level.downto(0) do |level|
          neighbors = search_level(graph, new_embedding, current, level, @ef_construction)

          # Select M best neighbors
          selected = select_neighbors(graph, new_embedding, neighbors, @m)

          graph[new_id][:neighbors][level] = selected

          # Add bidirectional connections
          selected.each do |neighbor_id|
            neighbor_neighbors = graph[neighbor_id][:neighbors][level] || []
            neighbor_neighbors << new_id

            # Prune if too many
            if neighbor_neighbors.size > @m * 2
              neighbor_embedding = graph[neighbor_id][:embedding]
              graph[neighbor_id][:neighbors][level] = select_neighbors(
                graph, neighbor_embedding, neighbor_neighbors, @m * 2
              )
            else
              graph[neighbor_id][:neighbors][level] = neighbor_neighbors
            end
          end

          current = selected.first if selected.any?
        end
      end

      def greedy_search_level(graph, query, entry, level)
        current = entry
        current_dist = cosine_distance(query, graph[current][:embedding])

        loop do
          changed = false
          neighbors = graph[current][:neighbors][level] || []

          neighbors.each do |neighbor|
            next unless graph[neighbor]

            dist = cosine_distance(query, graph[neighbor][:embedding])
            if dist < current_dist
              current = neighbor
              current_dist = dist
              changed = true
            end
          end

          break unless changed
        end

        current
      end

      def search_level(graph, query, entry, level, ef)
        visited = Set.new([entry])
        candidates = [[cosine_distance(query, graph[entry][:embedding]), entry]]
        results = candidates.dup

        while candidates.any?
          candidates.sort_by!(&:first)
          current_dist, current = candidates.shift

          break if results.any? && current_dist > results.last.first

          neighbors = graph[current][:neighbors][level] || []
          neighbors.each do |neighbor|
            next if visited.include?(neighbor)
            next unless graph[neighbor]

            visited << neighbor
            dist = cosine_distance(query, graph[neighbor][:embedding])

            if results.size < ef || dist < results.last.first
              candidates << [dist, neighbor]
              results << [dist, neighbor]
              results.sort_by!(&:first)
              results.pop if results.size > ef
            end
          end
        end

        results.map(&:last)
      end

      def select_neighbors(graph, query, candidates, m)
        return candidates if candidates.size <= m

        scored = candidates.map do |id|
          [cosine_distance(query, graph[id][:embedding]), id]
        end

        scored.sort_by(&:first).first(m).map(&:last)
      end

      def cosine_distance(a, b)
        dot = 0.0
        norm_a = 0.0
        norm_b = 0.0

        a.each_with_index do |val, i|
          dot += val * b[i]
          norm_a += val * val
          norm_b += b[i] * b[i]
        end

        similarity = dot / (Math.sqrt(norm_a) * Math.sqrt(norm_b) + 1e-10)
        1.0 - similarity
      end

      def store_passages(documents, graph_data)
        graph = graph_data[:graph]

        # Bulk insert passages
        passage_records = documents.map do |doc|
          node = graph[doc[:id]]
          # Store only level-0 neighbors (most important for search)
          neighbors = node[:neighbors][0] || []

          {
            leann_index_id: @index.id,
            external_id: doc[:id],
            text: doc[:text],
            metadata: doc[:metadata] || {},
            neighbors: neighbors,
            created_at: Time.current,
            updated_at: Time.current
          }
        end

        Passage.insert_all(passage_records)
      end

      def update_index_metadata(graph_data)
        @index.update!(
          config: (@index.config || {}).merge(
            "entry_point_id" => graph_data[:entry_point],
            "max_level" => graph_data[:max_level],
            "hnsw_m" => @m,
            "hnsw_ef_construction" => @ef_construction
          )
        )
      end

      def search_hnsw(query_embedding, entry_point_id, max_level, ef, embedding_provider, passages, limit)
        # Load passages with neighbors
        passage_map = @index.passages.index_by(&:external_id)

        return [] if passage_map.empty?

        # Get entry point
        entry = passage_map[entry_point_id]
        return [] unless entry

        # Cache for computed embeddings
        embedding_cache = {}

        get_embedding = lambda do |id|
          return embedding_cache[id] if embedding_cache[id]

          text = passages[id] || passage_map[id]&.text
          return nil unless text

          embedding_cache[id] = embedding_provider.compute([text]).first
        end

        entry_embedding = get_embedding.call(entry_point_id)
        return [] unless entry_embedding

        # Simple greedy search at level 0 (most passages only have level 0)
        visited = Set.new([entry_point_id])
        current_dist = cosine_distance(query_embedding, entry_embedding)
        candidates = [[current_dist, entry_point_id]]
        results = candidates.dup

        while candidates.any?
          candidates.sort_by!(&:first)
          dist, current_id = candidates.shift

          break if results.size >= ef && dist > results.last.first

          # Get neighbors from database
          current_passage = passage_map[current_id]
          next unless current_passage

          neighbors = current_passage.neighbor_ids

          neighbors.each do |neighbor_id|
            next if visited.include?(neighbor_id)

            visited << neighbor_id

            neighbor_embedding = get_embedding.call(neighbor_id)
            next unless neighbor_embedding

            neighbor_dist = cosine_distance(query_embedding, neighbor_embedding)

            if results.size < ef || neighbor_dist < results.last.first
              candidates << [neighbor_dist, neighbor_id]
              results << [neighbor_dist, neighbor_id]
              results.sort_by!(&:first)
              results.pop if results.size > ef
            end
          end
        end

        # Convert distances to similarity scores
        results.first(limit).map do |dist, id|
          score = 1.0 - dist
          [id, score]
        end
      end
    end
  end
end

# frozen_string_literal: true

require "json"

module Leann
  module Backend
    # LEANN Graph-only backend - stores only the HNSW graph structure
    # Achieves ~97% storage reduction by not storing embeddings
    #
    # Graph is stored as:
    # - Node levels (which layers each node participates in)
    # - Neighbor lists per level
    # - Entry point and HNSW parameters
    #
    # During search, embeddings are recomputed on-the-fly via API calls
    #
    class LeannGraph
      # HNSW parameters
      DEFAULT_M = 16           # Max connections per layer
      DEFAULT_EF_CONSTRUCTION = 200  # Build-time search width
      DEFAULT_ML = 1.0 / Math.log(DEFAULT_M)  # Level multiplier

      attr_reader :dimensions, :m, :ef_construction, :max_level, :entry_point
      attr_reader :node_count

      def initialize(dimensions:, m: DEFAULT_M, ef_construction: DEFAULT_EF_CONSTRUCTION)
        @dimensions = dimensions
        @m = m
        @m0 = m * 2  # Layer 0 has 2x connections
        @ef_construction = ef_construction
        @ml = 1.0 / Math.log(m)

        @nodes = []           # Array of node data {id:, level:}
        @id_to_idx = {}       # Map document ID to node index
        @neighbors = []       # neighbors[idx][level] = [neighbor_indices]
        @entry_point = nil
        @max_level = -1
        @node_count = 0
      end

      # Build the graph from embeddings
      # After building, embeddings can be discarded
      #
      # @param ids [Array<String>] Document IDs
      # @param embeddings [Array<Array<Float>>] Embedding vectors
      # @return [self]
      def build(ids, embeddings)
        raise ArgumentError, "IDs and embeddings must have same length" unless ids.length == embeddings.length
        return self if ids.empty?

        @node_count = ids.length
        puts "Building LEANN graph with #{@node_count} nodes (M=#{@m})..."

        ids.each_with_index do |id, idx|
          level = random_level
          @nodes << { id: id, level: level }
          @id_to_idx[id] = idx
          @neighbors << Array.new(level + 1) { [] }

          if @entry_point.nil?
            @entry_point = idx
            @max_level = level
          else
            # Insert node into graph
            insert_node(idx, embeddings[idx], embeddings, level)
          end

          print "." if (idx + 1) % 100 == 0
        end

        puts "\nGraph built: #{@node_count} nodes, max_level=#{@max_level}"
        self
      end

      # Save graph to files (no embeddings!)
      #
      # @param path [String] Base path for index files
      def save(path)
        graph_file = "#{path}.graph.bin"
        meta_file = "#{path}.graph.meta.json"

        # Save metadata
        meta = {
          version: "1.0",
          format: "leann_graph",
          node_count: @node_count,
          dimensions: @dimensions,
          m: @m,
          ef_construction: @ef_construction,
          max_level: @max_level,
          entry_point: @entry_point
        }
        File.write(meta_file, JSON.pretty_generate(meta))

        # Save graph in binary format
        File.open(graph_file, "wb") do |f|
          # Header
          f.write([@node_count].pack("Q<"))  # uint64 node count

          # Node levels
          levels = @nodes.map { |n| n[:level] }
          f.write(levels.pack("l<*"))  # int32 array

          # Node IDs (as length-prefixed strings)
          @nodes.each do |node|
            id_bytes = node[:id].to_s.encode("UTF-8")
            f.write([id_bytes.bytesize].pack("S<"))  # uint16 length
            f.write(id_bytes)
          end

          # Neighbor lists (CSR-like format)
          # First: offsets into neighbor data for each node
          offsets = []
          current_offset = 0
          @neighbors.each do |node_neighbors|
            offsets << current_offset
            node_neighbors.each do |level_neighbors|
              current_offset += level_neighbors.length
            end
          end
          offsets << current_offset  # Final offset

          f.write(offsets.pack("Q<*"))  # uint64 array

          # Level offsets within each node
          level_offsets = []
          @neighbors.each do |node_neighbors|
            level_offset = 0
            node_neighbors.each do |level_neighbors|
              level_offsets << level_offset
              level_offset += level_neighbors.length
            end
            level_offsets << level_offset  # End marker for this node
          end
          f.write([level_offsets.length].pack("Q<"))
          f.write(level_offsets.pack("Q<*"))

          # All neighbor indices (flattened)
          all_neighbors = @neighbors.flat_map { |nn| nn.flat_map { |ln| ln } }
          f.write([all_neighbors.length].pack("Q<"))
          f.write(all_neighbors.pack("l<*"))  # int32 array
        end

        graph_size = File.size(graph_file)
        puts "Graph saved: #{format_bytes(graph_size)} (no embeddings stored!)"
      end

      # Load graph from files
      #
      # @param path [String] Base path for index files
      # @return [LeannGraph]
      def self.load(path)
        graph_file = "#{path}.graph.bin"
        meta_file = "#{path}.graph.meta.json"

        raise IndexNotFoundError, "Graph file not found: #{graph_file}" unless File.exist?(graph_file)

        meta = JSON.parse(File.read(meta_file), symbolize_names: true)

        graph = new(
          dimensions: meta[:dimensions],
          m: meta[:m],
          ef_construction: meta[:ef_construction]
        )
        graph.load_from_files(path, meta)
        graph
      end

      # Load graph data from binary file
      def load_from_files(path, meta)
        graph_file = "#{path}.graph.bin"

        @node_count = meta[:node_count]
        @max_level = meta[:max_level]
        @entry_point = meta[:entry_point]

        File.open(graph_file, "rb") do |f|
          # Read node count
          node_count = f.read(8).unpack1("Q<")
          raise "Node count mismatch" unless node_count == @node_count

          # Read levels
          levels = f.read(@node_count * 4).unpack("l<*")

          # Read node IDs
          @nodes = []
          @id_to_idx = {}
          @node_count.times do |idx|
            id_len = f.read(2).unpack1("S<")
            id = f.read(id_len).force_encoding("UTF-8")
            @nodes << { id: id, level: levels[idx] }
            @id_to_idx[id] = idx
          end

          # Read offsets
          offsets = f.read((@node_count + 1) * 8).unpack("Q<*")

          # Read level offsets
          level_offsets_count = f.read(8).unpack1("Q<")
          level_offsets = f.read(level_offsets_count * 8).unpack("Q<*")

          # Read all neighbors
          neighbors_count = f.read(8).unpack1("Q<")
          all_neighbors = f.read(neighbors_count * 4).unpack("l<*")

          # Reconstruct neighbor structure
          @neighbors = []
          level_offset_idx = 0
          @node_count.times do |idx|
            node_level = levels[idx]
            node_neighbors = []
            base_offset = offsets[idx]

            (node_level + 1).times do |level|
              start_off = level_offsets[level_offset_idx]
              end_off = level_offsets[level_offset_idx + 1]
              level_offset_idx += 1

              level_neighbors = all_neighbors[(base_offset + start_off)...(base_offset + end_off)]
              node_neighbors << (level_neighbors || [])
            end
            level_offset_idx += 1  # Skip end marker

            @neighbors << node_neighbors
          end
        end

        puts "Graph loaded: #{@node_count} nodes, max_level=#{@max_level}"
      end

      # Search the graph using on-the-fly embedding computation
      #
      # @param query_embedding [Array<Float>] Query vector
      # @param embedding_provider [Embedding::Base] For recomputing embeddings
      # @param passages [Hash] id => text mapping for recomputation
      # @param limit [Integer] Number of results
      # @param ef [Integer] Search width (higher = more accurate, slower)
      # @return [Array<[String, Float]>] Array of [id, score] pairs
      def search(query_embedding, embedding_provider:, passages:, limit: 5, ef: nil)
        return [] if @entry_point.nil?

        ef ||= [limit * 2, 10].max

        # Cache for embeddings computed during this search
        embedding_cache = {}

        # Start from entry point, traverse down to layer 0
        current = @entry_point
        current_dist = distance(query_embedding, get_embedding(current, embedding_provider, passages, embedding_cache))

        # Greedy search from top layer down to layer 1
        (@max_level).downto(1) do |level|
          changed = true
          while changed
            changed = false
            neighbors = get_neighbors(current, level)
            neighbors.each do |neighbor|
              neighbor_emb = get_embedding(neighbor, embedding_provider, passages, embedding_cache)
              neighbor_dist = distance(query_embedding, neighbor_emb)
              if neighbor_dist < current_dist
                current = neighbor
                current_dist = neighbor_dist
                changed = true
              end
            end
          end
        end

        # Search layer 0 with ef-sized candidate set
        candidates = search_layer(query_embedding, current, ef, 0, embedding_provider, passages, embedding_cache)

        # Return top-k results, converted to similarity scores
        candidates
          .sort_by { |_, dist| dist }
          .first(limit)
          .map { |idx, dist| [@nodes[idx][:id], 1.0 - dist] }  # Convert distance to similarity
      end

      # Get neighbors at a specific level
      def get_neighbors(node_idx, level)
        return [] if node_idx >= @neighbors.length
        return [] if level >= @neighbors[node_idx].length
        @neighbors[node_idx][level] || []
      end

      # Get document ID for a node index
      def get_id(node_idx)
        @nodes[node_idx][:id]
      end

      # Get node index for a document ID
      def get_idx(id)
        @id_to_idx[id]
      end

      private

      def random_level
        level = 0
        while rand < (1.0 / @m) && level < 32
          level += 1
        end
        level
      end

      def distance(a, b)
        # Cosine distance = 1 - cosine_similarity
        dot = 0.0
        norm_a = 0.0
        norm_b = 0.0
        a.each_with_index do |val, i|
          dot += val * b[i]
          norm_a += val * val
          norm_b += b[i] * b[i]
        end
        norm_a = Math.sqrt(norm_a)
        norm_b = Math.sqrt(norm_b)
        return 1.0 if norm_a == 0 || norm_b == 0
        1.0 - (dot / (norm_a * norm_b))
      end

      def get_embedding(node_idx, embedding_provider, passages, cache)
        return cache[node_idx] if cache.key?(node_idx)

        id = @nodes[node_idx][:id]
        text = passages[id]
        raise "Passage not found for ID: #{id}" unless text

        embedding = embedding_provider.compute_one(text)
        cache[node_idx] = embedding
        embedding
      end

      def insert_node(idx, embedding, all_embeddings, level)
        # Find entry point for this insert
        ep = @entry_point
        ep_dist = distance(embedding, all_embeddings[ep])

        # Traverse from top to insertion level + 1
        (@max_level).downto(level + 1) do |lc|
          changed = true
          while changed
            changed = false
            get_neighbors(ep, lc).each do |neighbor|
              d = distance(embedding, all_embeddings[neighbor])
              if d < ep_dist
                ep = neighbor
                ep_dist = d
                changed = true
              end
            end
          end
        end

        # Insert at each level from insertion level down to 0
        [level, @max_level].min.downto(0) do |lc|
          # Search for closest neighbors at this level
          max_neighbors = lc == 0 ? @m0 : @m

          candidates = search_layer_build(embedding, ep, @ef_construction, lc, all_embeddings)
          neighbors = select_neighbors(embedding, candidates, max_neighbors, all_embeddings)

          # Add edges
          @neighbors[idx][lc] = neighbors

          # Add reverse edges
          neighbors.each do |neighbor|
            neighbor_neighbors = @neighbors[neighbor][lc]
            if neighbor_neighbors.length < max_neighbors
              neighbor_neighbors << idx
            else
              # Check if we should replace a neighbor
              candidates_with_new = neighbor_neighbors + [idx]
              new_neighbors = select_neighbors(
                all_embeddings[neighbor],
                candidates_with_new.map { |n| [n, distance(all_embeddings[neighbor], all_embeddings[n])] },
                max_neighbors,
                all_embeddings
              )
              @neighbors[neighbor][lc] = new_neighbors
            end
          end

          ep = neighbors.first if neighbors.any?
        end

        # Update entry point if needed
        if level > @max_level
          @entry_point = idx
          @max_level = level
        end
      end

      def search_layer_build(query_emb, entry_point, ef, level, all_embeddings)
        visited = Set.new([entry_point])
        candidates = [[entry_point, distance(query_emb, all_embeddings[entry_point])]]
        results = [[entry_point, candidates.first[1]]]

        while candidates.any?
          # Get closest unprocessed candidate
          candidates.sort_by! { |_, d| d }
          current, current_dist = candidates.shift

          # Stop if we've found enough and current is worse than worst result
          break if results.length >= ef && current_dist > results.last[1]

          # Explore neighbors
          get_neighbors(current, level).each do |neighbor|
            next if visited.include?(neighbor)
            visited.add(neighbor)

            neighbor_dist = distance(query_emb, all_embeddings[neighbor])

            if results.length < ef || neighbor_dist < results.last[1]
              candidates << [neighbor, neighbor_dist]
              results << [neighbor, neighbor_dist]
              results.sort_by! { |_, d| d }
              results.pop if results.length > ef
            end
          end
        end

        results
      end

      def search_layer(query_emb, entry_point, ef, level, embedding_provider, passages, cache)
        visited = Set.new([entry_point])
        entry_emb = get_embedding(entry_point, embedding_provider, passages, cache)
        candidates = [[entry_point, distance(query_emb, entry_emb)]]
        results = [[entry_point, candidates.first[1]]]

        while candidates.any?
          candidates.sort_by! { |_, d| d }
          current, current_dist = candidates.shift

          break if results.length >= ef && current_dist > results.last[1]

          get_neighbors(current, level).each do |neighbor|
            next if visited.include?(neighbor)
            visited.add(neighbor)

            neighbor_emb = get_embedding(neighbor, embedding_provider, passages, cache)
            neighbor_dist = distance(query_emb, neighbor_emb)

            if results.length < ef || neighbor_dist < results.last[1]
              candidates << [neighbor, neighbor_dist]
              results << [neighbor, neighbor_dist]
              results.sort_by! { |_, d| d }
              results.pop if results.length > ef
            end
          end
        end

        results
      end

      def select_neighbors(query_emb, candidates, max_count, all_embeddings)
        # Simple selection: take closest
        candidates
          .sort_by { |_, d| d.is_a?(Array) ? d[1] : d }
          .first(max_count)
          .map { |n, _| n.is_a?(Array) ? n[0] : n }
      end

      def format_bytes(bytes)
        if bytes < 1024
          "#{bytes} B"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(1)} KB"
        else
          "#{(bytes / (1024.0 * 1024)).round(2)} MB"
        end
      end
    end
  end
end

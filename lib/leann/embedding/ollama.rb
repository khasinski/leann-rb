# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "base"

module Leann
  module Embedding
    # Ollama Embeddings API provider
    #
    # Uses local Ollama server for computing embeddings.
    # Requires Ollama to be running: https://ollama.com
    #
    # @example
    #   provider = Leann::Embedding::Ollama.new(model: "nomic-embed-text")
    #   embeddings = provider.compute(["Hello", "World"])
    #
    class Ollama < Base
      DEFAULT_HOST = "http://localhost:11434"
      EMBED_PATH = "/api/embed"
      MAX_BATCH_SIZE = 32
      TIMEOUT = 60

      # Popular embedding models
      POPULAR_MODELS = %w[
        nomic-embed-text
        mxbai-embed-large
        bge-m3
        all-minilm
        snowflake-arctic-embed
      ].freeze

      # @param model [String] Ollama embedding model name
      # @param host [String, nil] Ollama server URL
      def initialize(model: "nomic-embed-text", host: nil)
        super(model: model)

        @host = host || Leann.configuration.ollama_host || ENV["OLLAMA_HOST"] || DEFAULT_HOST
        @dimensions = nil

        check_connection!
      end

      # Compute embeddings for texts
      #
      # @param texts [Array<String>]
      # @return [Array<Array<Float>>]
      def compute(texts)
        return [] if texts.empty?

        all_embeddings = []

        in_batches(texts, MAX_BATCH_SIZE) do |batch|
          batch_embeddings = compute_batch(batch)
          all_embeddings.concat(batch_embeddings)
          print "." # Progress indicator
        end

        puts " Done! (#{all_embeddings.size} embeddings)" unless texts.size < MAX_BATCH_SIZE

        # Normalize embeddings (Ollama may not normalize by default)
        all_embeddings.map { |emb| normalize(emb) }
      end

      private

      def check_connection!
        uri = URI.parse("#{@host}/api/version")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 5

        response = http.get(uri.request_uri)

        return if response.code.to_i == 200

        raise EmbeddingError.new(
          "Cannot connect to Ollama at #{@host}. Is Ollama running?",
          provider: :ollama
        )
      rescue Errno::ECONNREFUSED, Errno::ETIMEDOUT, Net::OpenTimeout => e
        raise EmbeddingError.new(
          connection_error_message,
          provider: :ollama,
          original_error: e
        )
      end

      def compute_batch(texts)
        uri = URI.parse("#{@host}#{EMBED_PATH}")

        body = {
          model: model,
          input: texts
        }

        response = make_request(uri, body)
        parse_response(response, texts.size)
      end

      def make_request(uri, body)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = TIMEOUT
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)

        response = http.request(request)

        case response.code.to_i
        when 200
          response
        when 404
          raise EmbeddingError.new(
            model_not_found_message,
            provider: :ollama
          )
        else
          error_message = parse_error(response)
          raise EmbeddingError.new(
            "Ollama API error: #{error_message}",
            provider: :ollama
          )
        end
      end

      def parse_response(response, expected_count)
        data = JSON.parse(response.body)
        embeddings = data["embeddings"]

        unless embeddings && embeddings.is_a?(Array)
          raise EmbeddingError.new(
            "Invalid response from Ollama: missing embeddings",
            provider: :ollama
          )
        end

        unless embeddings.size == expected_count
          raise EmbeddingError.new(
            "Ollama returned #{embeddings.size} embeddings, expected #{expected_count}",
            provider: :ollama
          )
        end

        embeddings
      rescue JSON::ParserError => e
        raise EmbeddingError.new(
          "Failed to parse Ollama response: #{e.message}",
          provider: :ollama,
          original_error: e
        )
      end

      def parse_error(response)
        data = JSON.parse(response.body)
        data["error"] || response.body
      rescue JSON::ParserError
        response.body
      end

      def connection_error_message
        <<~MSG
          Cannot connect to Ollama at #{@host}.

          Please ensure Ollama is running:
            macOS/Linux: ollama serve
            Windows: Make sure Ollama is running in the system tray

          Installation: https://ollama.com/download
        MSG
      end

      def model_not_found_message
        <<~MSG
          Model '#{model}' not found in Ollama.

          To install:
            ollama pull #{model}

          Popular embedding models:
            #{POPULAR_MODELS.map { |m| "ollama pull #{m}" }.join("\n  ")}

          Browse more: https://ollama.com/library
        MSG
      end
    end
  end
end

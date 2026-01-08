# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require_relative "base"

module Leann
  module Embedding
    # OpenAI Embeddings API provider
    #
    # @example
    #   provider = Leann::Embedding::OpenAI.new(model: "text-embedding-3-small")
    #   embeddings = provider.compute(["Hello", "World"])
    #
    class OpenAI < Base
      BASE_URL = "https://api.openai.com/v1/embeddings"
      MAX_BATCH_SIZE = 2048
      MAX_RETRIES = 3
      RETRY_DELAY = 1.0

      # Model dimensions lookup
      DIMENSIONS = {
        "text-embedding-3-small" => 1536,
        "text-embedding-3-large" => 3072,
        "text-embedding-ada-002" => 1536
      }.freeze

      # @param model [String] OpenAI embedding model name
      # @param api_key [String, nil] API key (defaults to ENV or config)
      # @param base_url [String, nil] Custom base URL
      def initialize(model: "text-embedding-3-small", api_key: nil, base_url: nil)
        super(model: model)

        @api_key = api_key || Leann.configuration.openai_api_key || ENV["OPENAI_API_KEY"]
        @base_url = base_url || Leann.configuration.openai_base_url || BASE_URL
        @dimensions = DIMENSIONS[model]

        validate_configuration!
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

        all_embeddings
      end

      private

      def validate_configuration!
        return if @api_key && !@api_key.empty?

        raise ConfigurationError, <<~MSG
          OpenAI API key is required.

          Set it via:
            - Environment: OPENAI_API_KEY=your-key
            - Configuration: Leann.configure { |c| c.openai_api_key = "your-key" }
            - Builder option: Leann.build("index", embedding: :openai, api_key: "your-key")
        MSG
      end

      def compute_batch(texts)
        uri = URI.parse(@base_url)

        body = {
          model: model,
          input: texts,
          encoding_format: "float"
        }

        response = make_request(uri, body)
        parse_response(response)
      end

      def make_request(uri, body, retries = 0)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 60
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@api_key}"
        request.body = JSON.generate(body)

        response = http.request(request)

        case response.code.to_i
        when 200
          response
        when 429, 500, 502, 503
          # Rate limit or server error - retry
          if retries < MAX_RETRIES
            delay = RETRY_DELAY * (2**retries)
            sleep(delay)
            make_request(uri, body, retries + 1)
          else
            raise EmbeddingError.new(
              "OpenAI API error after #{MAX_RETRIES} retries: #{response.code} #{response.body}",
              provider: :openai
            )
          end
        else
          error_message = parse_error(response)
          raise EmbeddingError.new(
            "OpenAI API error: #{error_message}",
            provider: :openai
          )
        end
      end

      def parse_response(response)
        data = JSON.parse(response.body)

        # Sort by index to ensure order matches input
        embeddings = data["data"].sort_by { |e| e["index"] }
        embeddings.map { |e| e["embedding"] }
      rescue JSON::ParserError => e
        raise EmbeddingError.new(
          "Failed to parse OpenAI response: #{e.message}",
          provider: :openai,
          original_error: e
        )
      end

      def parse_error(response)
        data = JSON.parse(response.body)
        data.dig("error", "message") || response.body
      rescue JSON::ParserError
        response.body
      end
    end
  end
end

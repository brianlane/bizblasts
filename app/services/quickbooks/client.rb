# frozen_string_literal: true

require 'httparty'

module Quickbooks
  class Client
    include HTTParty

    API_HOST = 'https://quickbooks.api.intuit.com'
    DEFAULT_MINORVERSION = 70

    def initialize(connection)
      @connection = connection
    end

    def realm_id
      @connection.realm_id
    end

    def get(path, query: {})
      request(:get, path, query: query)
    end

    def post(path, body: {}, query: {})
      request(:post, path, query: query, body: body)
    end

    def query(q)
      get("/v3/company/#{realm_id}/query", query: { query: q, minorversion: DEFAULT_MINORVERSION })
    end

    private

    def request(method, path, query: {}, body: nil)
      url = API_HOST + path

      headers = {
        'Authorization' => "Bearer #{@connection.access_token}",
        'Accept' => 'application/json',
        'Content-Type' => 'application/json'
      }

      options = { headers: headers, query: query }
      options[:body] = body.to_json if body

      response = self.class.send(method, url, **options)

      if response.code.to_i >= 400
        raise Quickbooks::RequestError.new(response)
      end

      response.parsed_response
    end
  end

  class RequestError < StandardError
    attr_reader :response

    def initialize(response)
      @response = response
      super(build_message)
    end

    def build_message
      code = response.code
      body = response.body.to_s
      "QuickBooks API request failed (#{code}): #{body.tr("\n", ' ')[0, 500]}"
    end
  end
end

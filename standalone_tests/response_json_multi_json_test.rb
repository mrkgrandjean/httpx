# frozen_string_literal: true

require "multi_json"
require "test_helper"

class ResponseYajlTest < Minitest::Test
  include HTTPX

  def test_response_decoders
    json_response = Response.new(request, 200, "2.0", { "content-type" => "application/json" })
    json_response << %({"a": "b"})
    assert json_response.json == { "a" => "b" }
    assert json_response.json(symbolize_keys: true) == { :a => "b" }
    json_response << "bogus"
    assert_raises(MultiJson::ParseError) { json_response.json }
  end

  private

  def request(verb = "GET", uri = "http://google.com")
    Request.new(verb, uri, Options.new)
  end

  def response(*args)
    Response.new(*args)
  end
end

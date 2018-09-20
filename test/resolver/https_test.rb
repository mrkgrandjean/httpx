# frozen_string_literal: true

require "ostruct"
require_relative "../test_helper"

class HTTPSResolverTest < Minitest::Test
  include ResolverHelpers
  include HTTPX

  def test_append_ipv4
    super
    assert resolver.empty?
  end

  def test_append_ipv6
    super
    assert resolver.empty?
  end

  def test_append_localhost
    super
    assert resolver.empty?
  end

  def test_parse_no_record
    @has_error = false
    resolver.on(:error) { @has_error = true }
    channel = build_channel("https://idontthinkthisexists.org/")
    resolver << channel
    resolver.queries["idontthinkthisexists.org"] = channel

    # this is only here to drain
    write_buffer.clear
    resolver.parse(no_record)
    assert channel.addresses.nil?
    assert resolver.queries.key?("idontthinkthisexists.org")
    assert !@has_error, "resolver should still be able to resolve AAAA"
    # A type
    write_buffer.clear
    resolver.parse(no_record)
    assert channel.addresses.nil?
    assert resolver.queries.key?("idontthinkthisexists.org")
    assert @has_error, "resolver should have failed"
  end

  def test_io_api
    __test_io_api
  end

  private

  def build_channel(*)
    channel = super
    connection.expect(:find_channel, channel, [URI::HTTP])
    channel
  end

  def resolver(options = Options.new)
    @resolver ||= begin
      resolver = Resolver::HTTPS.new(connection, options)
      resolver.extend(ResolverHelpers::ResolverExtensions)
      resolver
    end
  end

  def connection
    @connection ||= Minitest::Mock.new
  end

  def write_buffer
    resolver.instance_variable_get(:@resolver_channel)
            .instance_variable_get(:@pending)
  end

  MockResponse = Struct.new(:headers, :body) do
    def to_s
      body
    end
  end

  def a_record
    MockResponse.new({ "content-type" => "application/dns-udpwireformat" }, super)
  end

  def aaaa_record
    MockResponse.new({ "content-type" => "application/dns-udpwireformat" }, super)
  end

  def cname_record
    MockResponse.new({ "content-type" => "application/dns-udpwireformat" }, super)
  end

  def no_record
    MockResponse.new({ "content-type" => "application/dns-udpwireformat" }, super)
  end
end
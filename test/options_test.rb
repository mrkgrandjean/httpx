# frozen_string_literal: true

require_relative "test_helper"

class OptionsTest < Minitest::Test
  include HTTPX

  def test_options_unknown
    ex = assert_raises(Error) { Options.new(foo: "bar") }
    assert ex.message =~ /unknown option: foo/, ex.message
  end

  def test_options_def_option_plain
    opts = Class.new(Options) do
      def_option(:foo)
    end.new(foo: "1")
    assert opts.foo == "1", "foo wasn't set"
  end

  def test_options_def_option_str_eval
    opts = Class.new(Options) do
      def_option(:foo, <<-OUT)
        Integer(value)
      OUT
    end.new(foo: "1")
    assert opts.foo == 1, "foo wasn't set or converted"
  end

  def test_options_def_option_block
    bar = nil
    _opts = Class.new(Options) do
      def_option(:foo) do |value|
        bar = 2
        value
      end
    end.new(foo: "1")
    assert bar == 2, "bar hasn't been set"
  end unless RUBY_VERSION >= "3.0.0"

  def test_options_body
    opt1 = Options.new
    assert opt1.body.nil?, "body shouldn't be set by default"
    opt2 = Options.new(:body => "fat")
    assert opt2.body == "fat", "body was not set"
  end

  %i[form json].each do |meth|
    define_method :"test_options_#{meth}" do
      opt1 = Options.new
      assert opt1.public_send(meth).nil?, "#{meth} shouldn't be set by default"
      opt2 = Options.new(meth => { "foo" => "bar" })
      assert opt2.public_send(meth) == { "foo" => "bar" }, "#{meth} was not set"
    end
  end

  def test_options_headers
    opt1 = Options.new
    assert opt1.headers.to_a.empty?, "headers should be empty"
    opt2 = Options.new(:headers => { "accept" => "*/*" })
    assert opt2.headers.to_a == [%w[accept */*]], "headers are unexpected"
  end

  def test_options_merge
    opts = Options.new(body: "fat")
    assert opts.merge(body: "thin").body == "thin", "parameter hasn't been merged"
    assert opts.body == "fat", "original parameter has been mutated after merge"

    opt2 = Options.new(body: "short")
    assert opts.merge(opt2).body == "short", "options parameter hasn't been merged"

    foo = Options.new(
      :form => { :foo => "foo" },
      :headers => { :accept => "json", :foo => "foo" },
    )

    bar = Options.new(
      :form => { :bar => "bar" },
      :headers => { :accept => "xml", :bar => "bar" },
      :ssl => { :foo => "bar" },
    )

    expected = {
      :io => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
      :debug => nil,
      :debug_level => 1,
      :params => nil,
      :json => nil,
      :body => nil,
      :window_size => 16_384,
      :body_threshold_size => 114_688,
      :form => { :bar => "bar" },
      :timeout => {
        connect_timeout: 60,
        settings_timeout: 10,
        operation_timeout: 60,
        keep_alive_timeout: 20,
      },
      :ssl => { :foo => "bar" },
      :http2_settings => { :settings_enable_push => 0 },
      :fallback_protocol => "http/1.1",
      :headers => { "accept" => "xml", "foo" => "foo", "bar" => "bar" },
      :max_concurrent_requests => nil,
      :max_requests => nil,
      :request_class => bar.request_class,
      :response_class => bar.response_class,
      :headers_class => bar.headers_class,
      :request_body_class => bar.request_body_class,
      :response_body_class => bar.response_body_class,
      :connection_class => bar.connection_class,
      :transport => nil,
      :transport_options => nil,
      :addresses => nil,
      :persistent => false,
      :resolver_class => bar.resolver_class,
      :resolver_options => bar.resolver_options,
    }.reject { |_, value| value.nil? }

    assert foo.merge(bar).to_hash == expected, "options haven't merged correctly"
  end unless ENV.key?("HTTPX_DEBUG")

  def test_options_new
    opts = Options.new
    assert Options.new(opts) == opts, "it should have kept the same reference"
  end

  def test_options_to_hash
    opts = Options.new
    assert opts.to_hash.is_a?(Hash)
  end
end

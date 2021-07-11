# frozen_string_literal: true

module HTTPX
  class Options
    WINDOW_SIZE = 1 << 14 # 16K
    MAX_BODY_THRESHOLD_SIZE = (1 << 10) * 112 # 112K
    CONNECT_TIMEOUT = 60
    OPERATION_TIMEOUT = 60
    KEEP_ALIVE_TIMEOUT = 20
    SETTINGS_TIMEOUT = 10

    DEFAULT_OPTIONS = {
      :debug => ENV.key?("HTTPX_DEBUG") ? $stderr : nil,
      :debug_level => (ENV["HTTPX_DEBUG"] || 1).to_i,
      :ssl => {},
      :http2_settings => { settings_enable_push: 0 },
      :fallback_protocol => "http/1.1",
      :timeout => {
        connect_timeout: CONNECT_TIMEOUT,
        settings_timeout: SETTINGS_TIMEOUT,
        operation_timeout: OPERATION_TIMEOUT,
        keep_alive_timeout: KEEP_ALIVE_TIMEOUT,
      },
      :headers => {},
      :window_size => WINDOW_SIZE,
      :body_threshold_size => MAX_BODY_THRESHOLD_SIZE,
      :request_class => Class.new(Request),
      :response_class => Class.new(Response),
      :headers_class => Class.new(Headers),
      :request_body_class => Class.new(Request::Body),
      :response_body_class => Class.new(Response::Body),
      :connection_class => Class.new(Connection),
      :options_class => Class.new(self),
      :transport => nil,
      :transport_options => nil,
      :addresses => nil,
      :persistent => false,
      :resolver_class => (ENV["HTTPX_RESOLVER"] || :native).to_sym,
      :resolver_options => { cache: true },
    }.freeze

    class << self
      def new(options = {})
        # let enhanced options go through
        return options if self == Options && options.class > self
        return options if options.is_a?(self)

        super
      end

      def method_added(meth)
        super

        return unless meth =~ /^option_(.+)$/

        optname = Regexp.last_match(1).to_sym

        attr_reader(optname)

        class_eval(<<-OUT, __FILE__, __LINE__ + 1)
          def #{optname}=(value)
            return if value.nil?

            value = #{meth}(value)

            @#{optname} = value
          end
          protected :#{optname}=
        OUT
      end

      def def_option(optname, *args, &block)
        if args.size.zero? && !block_given?
          class_eval(<<-OUT, __FILE__, __LINE__ + 1)
            def option_#{optname}(v); v; end
          OUT
          return
        end

        deprecated_def_option(optname, *args, &block)
      end

      def deprecated_def_option(optname, layout = nil, &interpreter)
        warn "DEPRECATION WARNING: using `def_option(#{optname})` for setting options is deprecated. " \
          "Define module OptionsMethods and `def option_#{optname}(val)` instead."

        if layout
          class_eval(<<-OUT, __FILE__, __LINE__ + 1)
            def option_#{optname}(value)
              #{layout}
            end
          OUT
        elsif block_given?
          define_method(:"option_#{optname}") do |value|
            instance_exec(value, &interpreter)
          end
        end
      end
    end

    def initialize(options = {})
      defaults = DEFAULT_OPTIONS.merge(options)
      defaults.each do |(k, v)|
        next if v.nil?

        begin
          __send__(:"#{k}=", v)
        rescue NoMethodError
          raise Error, "unknown option: #{k}"
        end
      end
      freeze
    end

    def option_origin(value)
      URI(value)
    end

    def option_headers(value)
      if headers
        headers.merge(value)
      else
        Headers.new(value)
      end
    end

    def option_timeout(value)
      timeouts = Hash[value]

      if timeouts.key?(:loop_timeout)
        warn ":loop_timeout is deprecated, use :operation_timeout instead"
        timeouts[:operation_timeout] = timeouts.delete(:loop_timeout)
      end

      timeouts
    end

    def option_max_concurrent_requests(value)
      raise TypeError, ":max_concurrent_requests must be positive" unless value.positive?

      value
    end

    def option_max_requests(value)
      raise TypeError, ":max_requests must be positive" unless value.positive?

      value
    end

    def option_window_size(value)
      Integer(value)
    end

    def option_body_threshold_size(value)
      Integer(value)
    end

    def option_transport(value)
      transport = value.to_s
      raise TypeError, "\#{transport} is an unsupported transport type" unless IO.registry.key?(transport)

      transport
    end

    def option_addresses(value)
      Array(value)
    end

    %i[
      params form json body ssl http2_settings
      request_class response_class headers_class request_body_class
      response_body_class connection_class options_class
      io fallback_protocol debug debug_level transport_options resolver_class resolver_options
      persistent
    ].each do |method_name|
      def_option(method_name)
    end

    REQUEST_IVARS = %i[@params @form @json @body].freeze

    def ==(other)
      ivars = instance_variables | other.instance_variables
      ivars.all? do |ivar|
        case ivar
        when :@headers
          headers = instance_variable_get(ivar)
          headers.same_headers?(other.instance_variable_get(ivar))
        when *REQUEST_IVARS
          true
        else
          instance_variable_get(ivar) == other.instance_variable_get(ivar)
        end
      end
    end

    def merge(other)
      raise ArgumentError, "#{other.inspect} is not a valid set of options" unless other.respond_to?(:to_hash)

      h2 = other.to_hash
      return self if h2.empty?

      h1 = to_hash

      return self if h1 == h2

      merged = h1.merge(h2) do |k, v1, v2|
        case k
        when :headers, :ssl, :http2_settings, :timeout
          v1.merge(v2)
        else
          v2
        end
      end

      self.class.new(merged)
    end

    def to_hash
      hash_pairs = instance_variables.map do |ivar|
        [ivar[1..-1].to_sym, instance_variable_get(ivar)]
      end
      Hash[hash_pairs]
    end

    if RUBY_VERSION > "2.4.0"
      def initialize_dup(other)
        instance_variables.each do |ivar|
          instance_variable_set(ivar, other.instance_variable_get(ivar).dup)
        end
      end
    else
      def initialize_dup(other)
        instance_variables.each do |ivar|
          value = other.instance_variable_get(ivar)
          value = case value
                  when Symbol, Fixnum, TrueClass, FalseClass # rubocop:disable Lint/UnifiedInteger
                    value
                  else
                    value.dup
          end
          instance_variable_set(ivar, value)
        end
      end
    end
  end
end

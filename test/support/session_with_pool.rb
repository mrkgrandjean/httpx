# frozen_string_literal: true

module SessionWithPool
  module PoolMethods
    include HTTPX

    attr_reader :resolvers

    def resolver
      resolver_type = @options.resolver_class
      resolver_type = Resolver.resolver_for(resolver_type)

      resolver = @resolvers[resolver_type].first

      resolver = resolver.resolvers[0] if resolver.is_a?(Resolver::Multi)

      resolver
    end
  end

  module InstanceMethods
    attr_reader :pool, :connections_exausted, :connection_count, :ping_count, :connections

    def initialize(*)
      @connection_count = 0
      @connections_exausted = 0
      @ping_count = 0
      @connections = []
      super
    end

    private

    def do_init_connection(connection, *)
      super
      connection.on(:open) { @connection_count += 1 }
      connection.on(:pong) { @ping_count += 1 }
      connection.on(:exhausted) do
        @connections_exausted += 1
      end
      @connections << connection
    end
  end

  module ConnectionMethods
    attr_reader :origins

    def set_parser_callbacks(parser)
      super
      parser.on(:pong) { emit(:pong) }
    end
  end
end

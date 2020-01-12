# frozen_string_literal: true

require "strscan"

module HTTPX
  module AltSvc
    @altsvc_mutex = Mutex.new
    @altsvcs = Hash.new { |h, k| h[k] = [] }

    module_function

    def cached_altsvc(origin)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @altsvc_mutex.synchronize do
        lookup(origin, now)
      end
    end

    def cached_altsvc_set(origin, entry)
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @altsvc_mutex.synchronize do
        return if @altsvcs[origin].any? { |altsvc| altsvc["origin"] == entry["origin"] }

        entry["TTL"] = Integer(entry["ma"]) + now if entry.key?("ma")
        @altsvcs[origin] << entry
        entry
      end
    end

    def lookup(origin, ttl)
      return [] unless @altsvcs.key?(origin)

      @altsvcs[origin] = @altsvcs[origin].select do |entry|
        !entry.key?("TTL") || entry["TTL"] > ttl
      end
      @altsvcs[origin].reject { |entry| entry["noop"] }
    end

    def emit(request, response)
      # Alt-Svc
      return unless response.headers.key?("alt-svc")

      origin = request.origin
      host = request.uri.host
      parse(response.headers["alt-svc"]) do |alt_origin, alt_params|
        alt_origin.host ||= host
        yield(alt_origin, origin, alt_params)
      end
    end

    def parse(altsvc)
      return enum_for(__method__, altsvc) unless block_given?

      scanner = StringScanner.new(altsvc)
      until scanner.eos?
        alt_origin = scanner.scan(/[^=]+=("[^"]+"|[^;,]+)/)

        alt_params = []
        loop do
          alt_param = scanner.scan(/[^=]+=("[^"]+"|[^;,]+)/)
          alt_params << alt_param.strip if alt_param
          scanner.skip(/;/)
          break if scanner.eos? || scanner.scan(/ *, */)
        end
        alt_params = Hash[alt_params.map { |field| field.split("=") }]
        yield(parse_altsvc_origin(alt_origin), alt_params)
      end
    end

    # :nocov:
    if RUBY_VERSION < "2.2"
      def parse_altsvc_origin(alt_origin)
        alt_proto, alt_origin = alt_origin.split("=")
        alt_origin = alt_origin[1..-2] if alt_origin.start_with?("\"") && alt_origin.end_with?("\"")
        if alt_origin.start_with?(":")
          alt_origin = "dummy#{alt_origin}"
          uri = URI.parse(alt_origin)
          uri.host = nil
          uri
        else
          URI.parse("#{alt_proto}://#{alt_origin}")
        end
      end
    else
      def parse_altsvc_origin(alt_origin)
        alt_proto, alt_origin = alt_origin.split("=")
        alt_origin = alt_origin[1..-2] if alt_origin.start_with?("\"") && alt_origin.end_with?("\"")
        URI.parse("#{alt_proto}://#{alt_origin}")
      end
    end
    # :nocov:
  end
end

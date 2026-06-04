require "http/client"
require "openssl"
require "./device_info"
require "./error"

module SamsungTV
  # Thin wrapper over the TV's HTTP REST API. Only the device-info endpoint is
  # needed for status; everything else is driven over websockets.
  class REST
    def initialize(@host : String, @port : Int32, @tls : Bool, @timeout : Time::Span)
    end

    # Fetch and parse `GET /api/v2/`. Raises `ConnectionError` if the TV cannot
    # be reached (e.g. it is fully powered off) and `ResponseError` if the body
    # cannot be parsed.
    def device_info : DeviceInfo
      body = get("/api/v2/")
      DeviceInfo.from_json(body)
    rescue ex : JSON::ParseException
      raise ResponseError.new("could not parse device info: #{ex.message}")
    end

    # `true` when `device_info` succeeds. A fully powered-off TV refuses the
    # connection, so this doubles as a coarse "is the TV awake" probe.
    def reachable? : Bool
      device_info
      true
    rescue ConnectionError
      false
    end

    # Launch a Tizen application by id (`POST /api/v2/applications/<id>`).
    # Notably this works — and wakes the panel — even in deep standby, where
    # the secure remote websocket no longer grants sessions, and it requires
    # no token. Raises `ConnectionError` if the TV cannot be reached.
    def launch_app(app_id : String) : Nil
      request("POST", "/api/v2/applications/#{app_id}")
    end

    private def get(path : String) : String
      request("GET", path)
    end

    private def request(method : String, path : String) : String
      client = build_client
      begin
        response = client.exec(method, path)
        unless response.success?
          raise ConnectionError.new("REST #{method} #{path} returned #{response.status_code}")
        end
        response.body
      ensure
        client.close
      end
    rescue ex : IO::Error | Socket::Error | OpenSSL::SSL::Error
      raise ConnectionError.new("could not reach TV at #{@host}:#{@port}: #{ex.message}")
    end

    private def build_client : HTTP::Client
      client =
        if @tls
          HTTP::Client.new(@host, @port, tls: insecure_tls_context)
        else
          HTTP::Client.new(@host, @port)
        end
      client.connect_timeout = @timeout
      client.read_timeout = @timeout
      client
    end

    # The TV presents a self-signed certificate, so verification must be
    # disabled to talk to it over HTTPS.
    private def insecure_tls_context : OpenSSL::SSL::Context::Client
      ctx = OpenSSL::SSL::Context::Client.new
      ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      ctx
    end
  end
end

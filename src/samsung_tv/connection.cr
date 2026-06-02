require "http/web_socket"
require "openssl"
require "base64"
require "json"
require "uri"
require "socket"
require "./error"

module SamsungTV
  # A long-lived websocket connection to the TV's remote-control channel
  # (`samsung.remote.control`).
  #
  # It runs a background read-loop fiber that captures the auth token the TV
  # hands out on `ms.channel.connect`, keeps the connection alive, and forwards
  # any other events to an optional `on_event` callback. The connection is
  # opened once and reused for every key press.
  class Connection
    getter? connected : Bool
    getter token : String?

    @ws : HTTP::WebSocket?
    @on_event : Proc(String, JSON::Any, Nil)?
    @on_token : Proc(String, Nil)?

    # *endpoint* is the channel name (e.g. `"samsung.remote.control"`).
    def initialize(@host : String, @port : Int32, @endpoint : String,
                   @name : String, @tls : Bool, @timeout : Time::Span,
                   token : String? = nil)
      @token = token
      @connected = false
      @handshook = false
      @mutex = Mutex.new
      # Buffered so the read-loop fiber never blocks signalling the handshake
      # result, even if `connect` has already given up waiting.
      @handshake = Channel(Exception?).new(1)
    end

    # Register a callback invoked for every event other than the handshake.
    def on_event(&block : String, JSON::Any -> Nil) : Nil
      @on_event = block
    end

    # Register a callback invoked whenever the TV issues a new auth token.
    def on_token(&block : String -> Nil) : Nil
      @on_token = block
    end

    # Open the connection and complete the handshake. Idempotent.
    def connect : Nil
      return if @connected

      @handshook = false
      # Fresh per attempt so a stale result from a prior timed-out connect
      # cannot be read here.
      @handshake = Channel(Exception?).new(1)
      ws =
        begin
          HTTP::WebSocket.new(@host, channel_path, @port, tls_context)
        rescue ex : IO::Error | Socket::Error | OpenSSL::SSL::Error
          raise ConnectionError.new("could not connect to #{@endpoint}: #{ex.message}")
        end

      ws.on_message { |message| handle_message(message) }
      ws.on_close { |_code, _message| handle_close }
      @ws = ws

      spawn do
        ws.run
      rescue
        # Read loop ended (connection dropped) — handled by on_close / ensure.
      ensure
        handle_close
      end

      select
      when error = @handshake.receive
        if error
          close
          raise error
        end
      when timeout(@timeout)
        close
        raise TimeoutError.new("timed out completing handshake on #{@endpoint}")
      end

      @connected = true
    end

    def close : Nil
      @ws.try &.close
    rescue
      # Already closed.
    ensure
      handle_close
    end

    # Send a `SendRemoteKey` command. *cmd* is `"Click"` (default), or
    # `"Press"`/`"Release"` for press-and-hold sequences.
    def send_key(key : String, cmd : String = "Click") : Nil
      ensure_connected
      params = {
        "Cmd"          => cmd,
        "DataOfCmd"    => key,
        "Option"       => "false",
        "TypeOfRemote" => "SendRemoteKey",
      }
      send_raw({method: "ms.remote.control", params: params}.to_json)
    end

    private def ensure_connected : Nil
      connect unless @connected
    end

    private def send_raw(message : String) : Nil
      ws = @ws
      raise ConnectionError.new("not connected to #{@endpoint}") unless ws
      ws.send(message)
    rescue ex : IO::Error | Socket::Error
      raise ConnectionError.new("send failed on #{@endpoint}: #{ex.message}")
    end

    private def handle_message(raw : String) : Nil
      frame = JSON.parse(raw)
      event = frame["event"]?.try(&.as_s) || "*"

      case event
      when "ms.channel.connect"
        capture_token(frame)
        # `ms.channel.connect` completes the handshake. (Some firmwares also
        # emit `ms.channel.ready`, but 2024 Frame models never do, so we must
        # not block waiting for it.)
        signal_handshake(nil)
      when "ms.channel.ready"
        signal_handshake(nil)
      when "ms.channel.unauthorized"
        signal_handshake(UnauthorizedError.new("TV rejected the remote (not authorised)"))
      else
        @on_event.try &.call(event, frame)
      end
    rescue JSON::ParseException
      # Ignore frames we cannot parse.
    end

    private def capture_token(frame : JSON::Any) : Nil
      raw = frame.dig?("data", "token")
      return unless raw
      token = raw.as_s? || raw.as_i64?.try(&.to_s) || raw.as_i?.try(&.to_s)
      return unless token
      return if token == @token
      @token = token
      @on_token.try &.call(token)
    end

    private def signal_handshake(error : Exception?) : Nil
      @mutex.synchronize do
        return if @handshook
        @handshook = true
      end
      @handshake.send(error)
    end

    private def handle_close : Nil
      @connected = false
      @ws = nil
    end

    private def channel_path : String
      params = URI::Params.build do |form|
        form.add("name", Base64.strict_encode(@name))
        if @tls && (token = @token)
          form.add("token", token)
        end
      end
      "/api/v2/channels/#{@endpoint}?#{params}"
    end

    private def tls_context : OpenSSL::SSL::Context::Client?
      return nil unless @tls
      ctx = OpenSSL::SSL::Context::Client.new
      ctx.verify_mode = OpenSSL::SSL::VerifyMode::NONE
      ctx
    end
  end
end

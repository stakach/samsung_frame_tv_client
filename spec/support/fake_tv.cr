require "http/server"
require "json"

# An in-process stand-in for a Samsung Frame TV, used by the specs so they can
# run without real hardware. It serves the REST device-info endpoint and the
# remote-control websocket channel, recording every key it receives.
class FakeTV
  getter port : Int32
  property power_state : String? # "on" / "standby" / "" / nil (field absent)
  property? frame_tv : Bool
  property token : String

  @server : HTTP::Server

  def initialize(@frame_tv : Bool = true, @power_state : String? = "on",
                 @mac : String = "aa:bb:cc:dd:ee:ff", @token : String = "test-token-123")
    @remote_messages = [] of JSON::Any
    @mutex = Mutex.new
    @port = 0
    @server = build_server
  end

  # Bind to an ephemeral localhost port and start serving in the background.
  # Returns the chosen port.
  def start : Int32
    address = @server.bind_tcp("127.0.0.1", 0)
    @port = address.port
    spawn { @server.listen }
    @port
  end

  def stop : Nil
    @server.close
  end

  # All raw frames received on the remote-control channel.
  def remote_messages : Array(JSON::Any)
    @mutex.synchronize { @remote_messages.dup }
  end

  # The `DataOfCmd` of every `SendRemoteKey` frame, in order.
  def sent_keys : Array(String)
    remote_messages.compact_map do |frame|
      next unless frame["method"]?.try(&.as_s) == "ms.remote.control"
      frame["params"]?.try { |obj| obj["DataOfCmd"]?.try(&.as_s) }
    end
  end

  # The `Cmd` of every `SendRemoteKey` frame, in order (Click/Press/Release).
  def sent_cmds : Array(String)
    remote_messages.compact_map do |frame|
      next unless frame["method"]?.try(&.as_s) == "ms.remote.control"
      frame["params"]?.try { |obj| obj["Cmd"]?.try(&.as_s) }
    end
  end

  private def build_server : HTTP::Server
    ws_handler = HTTP::WebSocketHandler.new do |ws, context|
      handle_remote(ws) if context.request.path == "/api/v2/channels/samsung.remote.control"
    end

    HTTP::Server.new([ws_handler.as(HTTP::Handler)]) do |context|
      if context.request.path == "/api/v2/"
        context.response.content_type = "application/json"
        context.response.print(device_info_json)
      else
        context.response.respond_with_status(:not_found)
      end
    end
  end

  private def handle_remote(ws : HTTP::WebSocket) : Nil
    ws.on_message do |message|
      @mutex.synchronize { @remote_messages << JSON.parse(message) }
    end
    ws.send({event: "ms.channel.connect", data: {token: @token}, from: "host"}.to_json)
  end

  private def device_info_json : String
    device = {} of String => String
    device["wifiMac"] = @mac
    device["name"] = "Samsung Frame (test)"
    device["modelName"] = "UE43LS003"
    device["FrameTVSupport"] = @frame_tv ? "true" : "false"
    device["TokenAuthSupport"] = "true"
    if state = @power_state
      device["PowerState"] = state
    end

    {device: device, name: "Samsung Frame (test)", version: "2.0.25"}.to_json
  end
end

require "./error"
require "./key"
require "./power_state"
require "./device_info"
require "./rest"
require "./connection"
require "./wol"

module SamsungTV
  # High-level local client for a Samsung Frame TV.
  #
  # ```
  # tv = SamsungTV::Client.new("192.168.1.40", token_file: "/tmp/tv.token")
  #
  # tv.power_state # => SamsungTV::PowerState::On
  # tv.power_off   # screen off (standby)
  # tv.power_on    # back on
  #
  # tv.volume_up(3)
  # tv.mute
  # ```
  #
  # ### Power model
  # The TV is modelled as **On** or **Off**:
  #
  # * `On`  — REST reports `PowerState == "on"`.
  # * `Off` — `"standby"` (screen off, still on the network), unreachable, or
  #   any other value.
  #
  # "Art mode" is deliberately ignored: on Frame TVs it reports `PowerState ==
  # "on"` just like a normal source, and the art-app websocket exposes no usable
  # status on current (e.g. 2024) firmware. See the README for the local-only
  # investigation behind this.
  #
  # ### Pairing
  # Modern TVs (port 8002) require authorisation: the first connection makes the
  # TV show an "Allow / Deny" prompt and raises `UnauthorizedError`. Once the
  # user accepts, reconnecting yields a token (persisted to `token_file` when
  # given) that authenticates future sessions silently.
  #
  # ### Volume over HDMI eARC
  # Volume and mute are sent as relative remote-key presses, so they work
  # whether the TV uses its own speakers or an external amp over HDMI eARC (the
  # TV forwards the equivalent CEC command). There is no absolute level or
  # mute-state read-back over this API.
  class Client
    REMOTE_ENDPOINT = "samsung.remote.control"

    getter host : String
    getter port : Int32

    @tls : Bool
    @token : String?
    @mac : String?
    @device_info : DeviceInfo?
    @remote : Connection?

    # *host* is the TV's IP/hostname. *port* 8002 uses TLS + token auth (the
    # default for modern TVs); 8001 is plaintext. *tls* defaults to `port == 8002`.
    # *mac* enables Wake-on-LAN; if omitted it is learned from device info while
    # the TV is reachable.
    #
    # *power_off_hold* / *power_off_interval*: powering a Frame TV fully off
    # needs a *held* power key, and this firmware only honours a hold sent as
    # repeated `Press` frames (a single Press→Release just toggles art mode).
    # We therefore send a `Press` every *power_off_interval* for *power_off_hold*,
    # then a `Release`.
    def initialize(@host : String, *, @port : Int32 = 8002, token : String? = nil,
                   @token_file : String? = nil, @name : String = "CrystalRemote",
                   mac : String? = nil, @timeout : Time::Span = 5.seconds,
                   tls : Bool? = nil, @power_off_hold : Time::Span = 4.seconds,
                   @power_off_interval : Time::Span = 200.milliseconds)
      @tls = tls.nil? ? (@port == 8002) : tls
      @mac = mac
      @token = token || read_token_file
      @rest = REST.new(@host, @port, @tls, @timeout)
    end

    # ----- lifecycle -------------------------------------------------------

    # Open the remote-control connection (and complete the auth handshake).
    # Optional: the connection opens lazily on first use.
    def connect : Nil
      remote.connect
    end

    def close : Nil
      @remote.try &.close
    end

    def connected? : Bool
      !!@remote.try(&.connected?)
    end

    # The current auth token (updated after a successful handshake).
    def token : String?
      @token
    end

    # ----- status ----------------------------------------------------------

    # Fetch device info over REST. Cached; pass `force: true` to refetch.
    def device_info(force : Bool = false) : DeviceInfo
      if force || @device_info.nil?
        @device_info = @rest.device_info
      end
      @device_info.as(DeviceInfo)
    end

    # `true` if the TV answers its REST endpoint. Note this is `true` even in
    # standby — the TV stays on the network — so use `power_state` to tell
    # On from Off.
    def reachable? : Bool
      @rest.reachable?
    end

    # `true` if the TV advertises Frame-TV support.
    def frame_tv? : Bool
      device_info.frame_tv?
    rescue ConnectionError
      false
    end

    # The TV's MAC address (for Wake-on-LAN), learned from device info if not
    # supplied to the constructor. `nil` if unknown and the TV is unreachable.
    def mac : String?
      @mac ||= begin
        device_info.mac
      rescue ConnectionError
        nil
      end
    end

    # Current power state: `On` (`PowerState == "on"`) or `Off` (standby,
    # unreachable, or any other value).
    def power_state : PowerState
      device_info(force: true).on? ? PowerState::On : PowerState::Off
    rescue ConnectionError
      PowerState::Off
    end

    def on? : Bool
      power_state.on?
    end

    def off? : Bool
      power_state.off?
    end

    # ----- power -----------------------------------------------------------

    # Drive the TV to *target* (`On` or `Off`).
    def power_state=(target : PowerState) : Nil
      case target
      in .on?  then power_on
      in .off? then power_off
      end
    end

    # Launched over REST to wake a deeply-dozing TV (see `#wake_panel`). Any
    # installed app works; the browser is universally present.
    WAKE_APP_ID = "org.tizen.browser"

    # Turn the TV on. No-op if already on. Wakes a reachable standby TV via
    # `KEY_POWER` (falling back to a REST app launch in deep standby); falls
    # back to Wake-on-LAN if the TV is off the network entirely.
    def power_on : Nil
      if reachable?
        return if device_info(force: true).on?
        wake_panel
      else
        wake
      end
    end

    # Turn the TV off (standby / screen off). No-op if already off. On a Frame
    # TV this holds `KEY_POWER` (via repeated `Press` frames); on a non-Frame TV
    # a single click suffices.
    def power_off : Nil
      return if power_state.off?
      if frame_tv_or_assume?
        hold_key(Key::POWER, @power_off_hold)
      else
        remote.send_key(Key::POWER)
      end
    end

    # Switch a Frame TV into art mode. From `On` a single `KEY_POWER` toggles
    # straight into art. From standby the panel is woken first; once the TV
    # reports `On` and has had *settle* to finish waking (the UI silently drops
    # remote keys for the first few seconds), the art toggle is sent. No-op on
    # non-Frame TVs.
    #
    # NOTE: assumes the TV is *not already in art mode* — art mode reads as
    # `On` and cannot be distinguished locally, so calling this while art is
    # showing would toggle it back out of art.
    #
    # Raises `TimeoutError` if a woken TV does not report `On` within
    # *wake_timeout*; the art toggle is then deliberately not sent, as a late
    # press would flip a slow-waking TV straight back off.
    def art_mode(wake_timeout : Time::Span = 30.seconds, settle : Time::Span = 4.seconds) : Nil
      return unless frame_tv_or_assume?

      if power_state.off?
        wake_panel
        wait_for_power(PowerState::On, timeout: wake_timeout)
        sleep settle
      end
      remote.send_key(Key::POWER)
    end

    # Poll until the TV reports *target* power state, checking every
    # *poll_interval*. Raises `TimeoutError` if it has not reached the target
    # within *timeout*.
    def wait_for_power(target : PowerState, *, timeout : Time::Span = 30.seconds,
                       poll_interval : Time::Span = 500.milliseconds) : Nil
      deadline = Time.instant + timeout
      until power_state == target
        if Time.instant >= deadline
          raise TimeoutError.new("TV did not reach #{target} within #{timeout.total_seconds.round(1)}s")
        end
        sleep poll_interval
      end
    end

    # Send a Wake-on-LAN magic packet. Raises if the MAC address is unknown.
    def wake : Nil
      address = mac
      raise Error.new(
        "cannot wake: MAC address unknown (pass `mac:` or read device_info while the TV is reachable)"
      ) unless address
      WakeOnLAN.send(address, @host)
    end

    # ----- volume / mute ---------------------------------------------------

    def volume_up(steps : Int32 = 1) : Nil
      send_key(Key::VOLUME_UP, steps)
    end

    def volume_down(steps : Int32 = 1) : Nil
      send_key(Key::VOLUME_DOWN, steps)
    end

    # Toggle mute on/off (the remote API only exposes a toggle).
    def mute : Nil
      send_key(Key::MUTE)
    end

    # ----- media transport -------------------------------------------------
    #
    # These drive whatever is playing on screen (an app's player, USB media,
    # ...). They are no-ops when nothing is playing. There is no combined
    # play/pause toggle — Samsung exposes separate Play and Pause keys.

    def play : Nil
      send_key(Key::PLAY)
    end

    def pause : Nil
      send_key(Key::PAUSE)
    end

    def stop : Nil
      send_key(Key::STOP)
    end

    def fast_forward : Nil
      send_key(Key::FAST_FORWARD)
    end

    def rewind : Nil
      send_key(Key::REWIND)
    end

    # ----- raw remote ------------------------------------------------------

    # Send an arbitrary key code (see `SamsungTV::Key`) *times* times.
    def send_key(key : String, times : Int32 = 1) : Nil
      times.times { remote.send_key(key) }
    end

    # Press and hold *key* for *seconds*. The hold is sent as repeated `Press`
    # frames every `power_off_interval`, then a `Release` — this firmware
    # ignores the duration of a lone Press→Release and only registers a true
    # hold from a stream of Press frames.
    def hold_key(key : String, seconds : Time::Span) : Nil
      remote.send_key(key, "Press")
      elapsed = Time::Span.zero
      while elapsed < seconds
        sleep @power_off_interval
        elapsed += @power_off_interval
        remote.send_key(key, "Press")
      end
      remote.send_key(key, "Release")
    end

    # ----- internals -------------------------------------------------------

    # Wake a standby panel. `KEY_POWER` over the websocket works in light
    # standby, but after a longer doze the TV stops granting secure remote
    # sessions while the screen is off (it also cannot show the auth prompt),
    # so the handshake times out. Launching any app over REST still works in
    # that state — and wakes the TV — at the cosmetic cost of the browser
    # being on screen briefly.
    private def wake_panel : Nil
      remote.send_key(Key::POWER)
    rescue ConnectionError | TimeoutError
      @rest.launch_app(WAKE_APP_ID)
    end

    private def frame_tv_or_assume? : Bool
      device_info.frame_tv?
    rescue ConnectionError
      # This is a Frame-TV library; default to the safe hold behaviour.
      true
    end

    private def remote : Connection
      @remote ||= begin
        conn = Connection.new(@host, @port, REMOTE_ENDPOINT, @name, @tls, @timeout, @token)
        conn.on_token { |new_token| store_token(new_token) }
        conn
      end
    end

    private def store_token(new_token : String) : Nil
      @token = new_token
      if file = @token_file
        File.write(file, new_token)
      end
    end

    private def read_token_file : String?
      file = @token_file
      return nil unless file && File.exists?(file)
      content = File.read(file).strip
      content.empty? ? nil : content
    end
  end
end

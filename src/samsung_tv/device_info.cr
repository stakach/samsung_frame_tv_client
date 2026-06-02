require "json"

module SamsungTV
  # Parsed response of `GET http(s)://<host>:<port>/api/v2/`.
  #
  # The TV reports most flags as the *strings* `"true"`/`"false"` and power as
  # `"on"`/`"off"`, so the helper predicates below normalise them.
  struct DeviceInfo
    include JSON::Serializable

    # The nested per-device block. All of its fields are optional because the
    # exact set varies by model and firmware.
    struct Device
      include JSON::Serializable

      @[JSON::Field(key: "PowerState")]
      getter power_state : String?

      @[JSON::Field(key: "FrameTVSupport")]
      getter frame_tv_support : String?

      @[JSON::Field(key: "TokenAuthSupport")]
      getter token_auth_support : String?

      @[JSON::Field(key: "wifiMac")]
      getter wifi_mac : String?

      getter name : String?

      @[JSON::Field(key: "modelName")]
      getter model_name : String?

      getter id : String?
    end

    getter device : Device?
    getter name : String?
    getter version : String?

    # `true` when the TV advertises Frame-TV (art mode) support.
    def frame_tv? : Bool
      device.try(&.frame_tv_support).to_s.downcase == "true"
    end

    # `true` when the TV requires token-based authentication (modern Tizen TVs
    # on port 8002).
    def token_auth? : Bool
      device.try(&.token_auth_support).to_s.downcase == "true"
    end

    # Reported power state as a lowercase string. Observed values: `"on"`,
    # `"standby"` (screen off), `""` (empty, also off) or `nil` when absent.
    def reported_power : String?
      device.try(&.power_state).try(&.downcase)
    end

    # `true` only when the TV reports it is on. Note a Frame TV in art mode also
    # reports `"on"`.
    def on? : Bool
      reported_power == "on"
    end

    # MAC address of the TV (used for Wake-on-LAN), or `nil` if unknown.
    def mac : String?
      device.try(&.wifi_mac)
    end

    def model_name : String?
      device.try(&.model_name)
    end
  end
end

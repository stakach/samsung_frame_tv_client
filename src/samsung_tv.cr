# Client library for monitoring and controlling a Samsung Frame TV.
#
# It speaks the modern Tizen websocket protocol (the same one the Home Assistant
# integration uses) to report power state — `Off`, `Art` (frame/picture mode) or
# `On` — and to control power, volume and mute.
#
# See `SamsungTV::Client` for the public API.
#
# ```
# require "samsung_tv"
#
# tv = SamsungTV::Client.new("192.168.1.40", token_file: "/var/lib/tv.token")
# puts tv.power_state
# tv.volume_up(2)
# ```
module SamsungTV
  VERSION = "0.1.0"
end

require "./samsung_tv/error"
require "./samsung_tv/key"
require "./samsung_tv/power_state"
require "./samsung_tv/device_info"
require "./samsung_tv/rest"
require "./samsung_tv/connection"
require "./samsung_tv/wol"
require "./samsung_tv/client"

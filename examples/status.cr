# Query a Samsung Frame TV's status (local only).
#
#   crystal run examples/status.cr -- 192.168.4.39
#
require "../src/samsung_tv"

host = ARGV[0]? || abort "usage: status.cr <tv-host-or-ip>"

tv = SamsungTV::Client.new(
  host,
  token_file: "/tmp/samsung_tv.token", # persist pairing token between runs
  name: "CrystalRemote",
  timeout: 10.seconds,
)

puts "reachable?: #{tv.reachable?}"

info = tv.device_info
puts "name:        #{info.name}"
puts "model:       #{info.model_name}"
puts "frame_tv?:   #{info.frame_tv?}"
puts "PowerState:  #{info.reported_power.inspect}"
puts "mac:         #{info.mac.inspect}"

# On (PowerState "on") vs Off (standby / unreachable / anything else).
puts "power_state: #{tv.power_state}"

tv.close

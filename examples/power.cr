# Turn a Samsung Frame TV on or off (local only).
#
#   crystal run examples/power.cr -- 192.168.4.39 on    # wake from standby
#   crystal run examples/power.cr -- 192.168.4.39 off   # screen off (standby)
#
# NOTE: this changes the TV's power state. "off" puts the panel into standby
# (screen off) by holding KEY_POWER; "on" wakes it (or sends Wake-on-LAN if the
# TV has dropped off the network).
require "../src/samsung_tv"

host = ARGV[0]? || abort "usage: power.cr <tv-host-or-ip> <on|off>"
action = ARGV[1]? || abort "usage: power.cr <tv-host-or-ip> <on|off>"

tv = SamsungTV::Client.new(
  host,
  token_file: "/tmp/samsung_tv.token",
  name: "CrystalRemote",
  timeout: 10.seconds,
)

puts "current power_state: #{tv.power_state}"

case action
when "on"  then tv.power_on
when "off" then tv.power_off
else
  abort "unknown action #{action.inspect} (expected on/off)"
end

puts "requested: #{action}"
tv.close

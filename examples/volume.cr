# Control volume and mute on a Samsung Frame TV.
#
#   crystal run examples/volume.cr -- 192.168.4.39
#
# The first connection on port 8002 makes the TV show an "Allow / Deny" prompt;
# accept it within the timeout. The token is then saved to `token_file` and
# reused silently on later runs (no prompt).
#
# Volume/mute are relative remote-key presses, so they also work when audio is
# routed over HDMI eARC — the TV forwards the equivalent CEC command to the amp.
require "../src/samsung_tv"

host = ARGV[0]? || abort "usage: volume.cr <tv-host-or-ip>"

tv = SamsungTV::Client.new(
  host,
  token_file: "/tmp/samsung_tv.token",
  name: "CrystalRemote",
  timeout: 30.seconds,
)

puts "Connecting (accept the prompt on the TV if it appears)..."
begin
  tv.connect
rescue ex : SamsungTV::UnauthorizedError
  abort "TV denied the remote — accept the prompt and re-run."
end
puts "Connected. token=#{tv.token.inspect}"

puts "volume_up(2)..."
tv.volume_up(2)
sleep 1.second

puts "volume_down(2)..."
tv.volume_down(2)
sleep 1.second

puts "mute (toggle)..."
tv.mute
sleep 1.5.seconds

puts "mute again (toggle back)..."
tv.mute

puts "done."
tv.close

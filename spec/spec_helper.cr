require "spec"
require "../src/samsung_tv"
require "./support/fake_tv"

# Spin up a `FakeTV`, hand a connected `SamsungTV::Client` to the block, and
# tear both down afterwards. The power-off hold is shrunk to keep specs fast.
def with_fake_tv(**tv_options, &)
  tv = FakeTV.new(**tv_options)
  port = tv.start
  client = SamsungTV::Client.new(
    "127.0.0.1",
    port: port,
    tls: false,
    timeout: 2.seconds,
    power_off_hold: 30.milliseconds,
    power_off_interval: 10.milliseconds,
  )
  begin
    yield client, tv
  ensure
    client.close
    tv.stop
  end
end

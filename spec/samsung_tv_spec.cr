require "./spec_helper"

# Poll *block* until it returns truthy, or fail after *timeout*. Used because
# fire-and-forget key presses are recorded by the fake TV's server fiber
# asynchronously.
def wait_until(timeout : Time::Span = 2.seconds, &)
  deadline = Time.instant + timeout
  until yield
    raise "condition not met within #{timeout}" if Time.instant > deadline
    sleep 5.milliseconds
  end
end

def free_port : Int32
  server = TCPServer.new("127.0.0.1", 0)
  port = server.local_address.port
  server.close
  port
end

describe SamsungTV::Client do
  describe "#device_info" do
    it "parses the Frame TV device info" do
      with_fake_tv(frame_tv: true, power_state: "on") do |client, _tv|
        info = client.device_info
        info.frame_tv?.should be_true
        info.token_auth?.should be_true
        info.reported_power.should eq("on")
        info.mac.should eq("aa:bb:cc:dd:ee:ff")
        info.model_name.should eq("UE43LS003")
      end
    end

    it "exposes the MAC address" do
      with_fake_tv do |client, _tv|
        client.mac.should eq("aa:bb:cc:dd:ee:ff")
      end
    end
  end

  describe "#power_state" do
    it "is On when PowerState is \"on\"" do
      with_fake_tv(power_state: "on") do |client, _tv|
        client.power_state.should eq(SamsungTV::PowerState::On)
        client.on?.should be_true
      end
    end

    it "is Off when PowerState is \"standby\"" do
      with_fake_tv(power_state: "standby") do |client, _tv|
        client.power_state.should eq(SamsungTV::PowerState::Off)
        client.off?.should be_true
      end
    end

    it "is Off when PowerState is empty" do
      with_fake_tv(power_state: "") do |client, _tv|
        client.power_state.should eq(SamsungTV::PowerState::Off)
      end
    end

    it "is Off when the TV is unreachable" do
      client = SamsungTV::Client.new(
        "127.0.0.1", port: free_port, tls: false, timeout: 500.milliseconds
      )
      client.reachable?.should be_false
      client.power_state.should eq(SamsungTV::PowerState::Off)
    end
  end

  describe "#power_on" do
    it "sends KEY_POWER to wake a reachable standby TV" do
      with_fake_tv(power_state: "standby") do |client, fake_tv|
        client.power_on
        wait_until { fake_tv.sent_keys.size == 1 }
        fake_tv.sent_keys.should eq(["KEY_POWER"])
        fake_tv.sent_cmds.should eq(["Click"])
      end
    end

    it "does nothing when already on" do
      with_fake_tv(power_state: "on") do |client, fake_tv|
        client.power_on
        sleep 50.milliseconds
        fake_tv.sent_keys.should be_empty
      end
    end
  end

  describe "#power_off" do
    it "holds KEY_POWER via repeated Press frames on a Frame TV" do
      with_fake_tv(frame_tv: true, power_state: "on") do |client, fake_tv|
        client.power_off
        wait_until { fake_tv.sent_cmds.last? == "Release" }

        fake_tv.sent_keys.uniq.should eq(["KEY_POWER"])
        cmds = fake_tv.sent_cmds
        cmds.first.should eq("Press")
        cmds.last.should eq("Release")
        cmds.count("Press").should be > 1 # a held key, not a single click
      end
    end

    it "clicks KEY_POWER once on a non-Frame TV" do
      with_fake_tv(frame_tv: false, power_state: "on") do |client, fake_tv|
        client.power_off
        wait_until { fake_tv.sent_keys.size == 1 }
        fake_tv.sent_keys.should eq(["KEY_POWER"])
        fake_tv.sent_cmds.should eq(["Click"])
      end
    end

    it "does nothing when already off" do
      with_fake_tv(power_state: "standby") do |client, fake_tv|
        client.power_off
        sleep 50.milliseconds
        fake_tv.sent_keys.should be_empty
      end
    end
  end

  describe "deep-standby wake fallback" do
    # A dozing TV answers REST but never completes the remote-channel
    # handshake; waking must fall back to a REST app launch.
    it "#power_on launches an app over REST when the remote channel is dead" do
      fake_tv = FakeTV.new(power_state: "standby", accept_remote: false)
      port = fake_tv.start
      client = SamsungTV::Client.new(
        "127.0.0.1", port: port, tls: false, timeout: 300.milliseconds
      )

      begin
        client.power_on
        fake_tv.launched_apps.should eq([SamsungTV::Client::WAKE_APP_ID])
        fake_tv.sent_keys.should be_empty
      ensure
        client.close
        fake_tv.stop
      end
    end

    it "#art_mode wakes via REST then toggles art once the TV reports On" do
      fake_tv = FakeTV.new(frame_tv: true, power_state: "standby", accept_remote: false)
      port = fake_tv.start
      client = SamsungTV::Client.new(
        "127.0.0.1", port: port, tls: false, timeout: 300.milliseconds
      )

      begin
        done = Channel(Exception?).new(1)
        spawn do
          client.art_mode(wake_timeout: 2.seconds, settle: 10.milliseconds)
          done.send(nil)
        rescue ex
          done.send(ex)
        end

        wait_until { fake_tv.launched_apps.size == 1 }

        # The TV wakes: REST reports on and the remote channel works again.
        fake_tv.power_state = "on"
        fake_tv.accept_remote = true

        done.receive.should be_nil
        fake_tv.launched_apps.should eq([SamsungTV::Client::WAKE_APP_ID])
        wait_until { fake_tv.sent_keys.size == 1 }
        fake_tv.sent_keys.should eq(["KEY_POWER"]) # the on -> art toggle
      ensure
        client.close
        fake_tv.stop
      end
    end
  end

  describe "#art_mode" do
    it "wakes the TV, waits for On, then toggles into art mode" do
      with_fake_tv(frame_tv: true, power_state: "standby") do |client, fake_tv|
        done = Channel(Exception?).new(1)
        spawn do
          client.art_mode(wake_timeout: 2.seconds, settle: 10.milliseconds)
          done.send(nil)
        rescue ex
          done.send(ex)
        end

        # First press goes out while the TV still reports standby...
        wait_until { fake_tv.sent_keys.size == 1 }
        sleep 50.milliseconds
        fake_tv.sent_keys.size.should eq(1) # ...and the second waits for On

        # TV wakes; the second press should follow.
        fake_tv.power_state = "on"
        wait_until { fake_tv.sent_keys.size == 2 }

        done.receive.should be_nil
        fake_tv.sent_keys.should eq(["KEY_POWER", "KEY_POWER"])
        fake_tv.sent_cmds.should eq(["Click", "Click"])
      end
    end

    it "gives up without the second press if the TV never wakes" do
      with_fake_tv(frame_tv: true, power_state: "standby") do |client, fake_tv|
        expect_raises(SamsungTV::TimeoutError) do
          client.art_mode(wake_timeout: 100.milliseconds)
        end
        fake_tv.sent_keys.should eq(["KEY_POWER"]) # wake press only
      end
    end

    it "toggles straight into art with a single press when the TV is on" do
      with_fake_tv(frame_tv: true, power_state: "on") do |client, fake_tv|
        client.art_mode(wake_timeout: 100.milliseconds)
        wait_until { fake_tv.sent_keys.size == 1 }
        fake_tv.sent_keys.should eq(["KEY_POWER"])
        fake_tv.sent_cmds.should eq(["Click"])
      end
    end

    it "does nothing on a non-Frame TV" do
      with_fake_tv(frame_tv: false, power_state: "standby") do |client, fake_tv|
        client.art_mode(wake_timeout: 100.milliseconds)
        sleep 50.milliseconds
        fake_tv.sent_keys.should be_empty
      end
    end
  end

  describe "#wait_for_power" do
    it "returns once the TV reaches the target state" do
      with_fake_tv(power_state: "standby") do |client, fake_tv|
        spawn do
          sleep 50.milliseconds
          fake_tv.power_state = "on"
        end
        client.wait_for_power(SamsungTV::PowerState::On, timeout: 2.seconds, poll_interval: 10.milliseconds)
        client.power_state.should eq(SamsungTV::PowerState::On)
      end
    end

    it "raises TimeoutError when the state never changes" do
      with_fake_tv(power_state: "standby") do |client, _tv|
        expect_raises(SamsungTV::TimeoutError) do
          client.wait_for_power(SamsungTV::PowerState::On, timeout: 50.milliseconds, poll_interval: 10.milliseconds)
        end
      end
    end
  end

  describe "volume / mute" do
    it "#volume_up sends KEY_VOLUP per step" do
      with_fake_tv do |client, fake_tv|
        client.volume_up(3)
        wait_until { fake_tv.sent_keys.size == 3 }
        fake_tv.sent_keys.should eq(["KEY_VOLUP", "KEY_VOLUP", "KEY_VOLUP"])
        fake_tv.sent_cmds.uniq.should eq(["Click"])
      end
    end

    it "#volume_down sends KEY_VOLDOWN" do
      with_fake_tv do |client, fake_tv|
        client.volume_down
        wait_until { fake_tv.sent_keys.size == 1 }
        fake_tv.sent_keys.should eq(["KEY_VOLDOWN"])
      end
    end

    it "#mute toggles via KEY_MUTE" do
      with_fake_tv do |client, fake_tv|
        client.mute
        wait_until { fake_tv.sent_keys.size == 1 }
        fake_tv.sent_keys.should eq(["KEY_MUTE"])
      end
    end
  end

  describe "media transport" do
    {
      "play"         => "KEY_PLAY",
      "pause"        => "KEY_PAUSE",
      "stop"         => "KEY_STOP",
      "fast_forward" => "KEY_FF",
      "rewind"       => "KEY_REWIND",
    }.each do |method, key|
      it "##{method} sends #{key}" do
        with_fake_tv do |client, fake_tv|
          case method
          when "play"         then client.play
          when "pause"        then client.pause
          when "stop"         then client.stop
          when "fast_forward" then client.fast_forward
          when "rewind"       then client.rewind
          end
          wait_until { fake_tv.sent_keys.size == 1 }
          fake_tv.sent_keys.should eq([key])
          fake_tv.sent_cmds.should eq(["Click"])
        end
      end
    end
  end

  describe "#send_key" do
    it "sends an arbitrary key the requested number of times" do
      with_fake_tv do |client, fake_tv|
        client.send_key(SamsungTV::Key::HOME, 2)
        wait_until { fake_tv.sent_keys.size == 2 }
        fake_tv.sent_keys.should eq(["KEY_HOME", "KEY_HOME"])
      end
    end
  end

  describe "authentication" do
    it "captures the token and persists it to the token file" do
      fake_tv = FakeTV.new(token: "abc-token")
      port = fake_tv.start
      file = File.tempname("samsung_tv", ".token")

      begin
        client = SamsungTV::Client.new(
          "127.0.0.1", port: port, tls: false, token_file: file, timeout: 2.seconds
        )
        client.connect
        wait_until { client.token == "abc-token" }

        client.token.should eq("abc-token")
        File.read(file).strip.should eq("abc-token")
        client.close
      ensure
        fake_tv.stop
        File.delete(file) if File.exists?(file)
      end
    end
  end
end

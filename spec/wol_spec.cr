require "./spec_helper"

describe SamsungTV::WakeOnLAN do
  describe ".packet" do
    it "builds a 102-byte magic packet" do
      packet = SamsungTV::WakeOnLAN.packet("aa:bb:cc:dd:ee:ff")
      mac = Bytes[0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff]

      packet.size.should eq(102)
      packet[0, 6].should eq(Bytes.new(6, 0xFF_u8))
      packet[6, 6].should eq(mac)  # first MAC repetition
      packet[96, 6].should eq(mac) # 16th (last) MAC repetition
    end

    it "accepts dash-separated MAC addresses" do
      SamsungTV::WakeOnLAN.packet("AA-BB-CC-DD-EE-FF")[6, 6]
        .should eq(Bytes[0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
    end

    it "rejects malformed MAC addresses" do
      expect_raises(ArgumentError) { SamsungTV::WakeOnLAN.packet("not-a-mac") }
      expect_raises(ArgumentError) { SamsungTV::WakeOnLAN.packet("aa:bb:cc") }
    end
  end

  describe ".send" do
    it "transmits the magic packet over UDP" do
      socket = UDPSocket.new
      socket.bind("127.0.0.1", 0)
      socket.read_timeout = 2.seconds
      port = socket.local_address.port

      SamsungTV::WakeOnLAN.send("aa:bb:cc:dd:ee:ff", "127.0.0.1", port: port, broadcast: false)

      buffer = Bytes.new(128)
      bytes_read, _ = socket.receive(buffer)
      bytes_read.should eq(102)
      buffer[0, 6].should eq(Bytes.new(6, 0xFF_u8))
      buffer[6, 6].should eq(Bytes[0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])
    ensure
      socket.try &.close
    end
  end
end

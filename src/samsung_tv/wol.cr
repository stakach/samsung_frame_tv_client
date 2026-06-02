require "socket"

module SamsungTV
  # Wake-on-LAN: the only way to power a Samsung TV back on once the panel is
  # fully off, since every network service (websocket + REST) is down in that
  # state. A "magic packet" is broadcast on the LAN; the TV's NIC wakes the set
  # when it sees its own MAC repeated in the payload.
  module WakeOnLAN
    # Build the 102-byte magic packet for *mac*: six `0xFF` bytes followed by
    # the 6-byte MAC repeated 16 times. Accepts `:` or `-` separated MACs.
    def self.packet(mac : String) : Bytes
      octets = mac.split(/[:\-]/).map do |part|
        part.to_u8(16) { raise ArgumentError.new("invalid MAC address: #{mac}") }
      end
      raise ArgumentError.new("invalid MAC address: #{mac}") unless octets.size == 6

      io = IO::Memory.new(102)
      6.times { io.write_byte(0xFF_u8) }
      16.times { octets.each { |octet| io.write_byte(octet) } }
      io.to_slice
    end

    # Send the magic packet for *mac*. By default it is broadcast to the LAN
    # and, if *host* is given, also sent directly to that address (helpful when
    # the broadcast domain or the TV's IP has changed).
    def self.send(mac : String, host : String? = nil, *, port : Int32 = 9,
                  broadcast : Bool = true) : Nil
      data = packet(mac)

      if broadcast
        socket = UDPSocket.new
        begin
          socket.broadcast = true
          socket.send(data, Socket::IPAddress.new("255.255.255.255", port))
        ensure
          socket.close
        end
      end

      if host
        socket = UDPSocket.new
        begin
          socket.connect(host, port)
          socket.send(data)
        ensure
          socket.close
        end
      end
    end
  end
end

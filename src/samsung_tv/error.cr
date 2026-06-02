module SamsungTV
  # Base class for every error raised by this library.
  class Error < Exception
  end

  # Raised when a connection to the TV cannot be established or is lost
  # (TV powered off, wrong port, network unreachable, ...).
  class ConnectionError < Error
  end

  # Raised when the TV rejects the connection because the remote has not been
  # authorised. On first connect the TV shows an "Allow / Deny" prompt; until
  # the user accepts, the websocket closes with `ms.channel.unauthorized`.
  class UnauthorizedError < ConnectionError
  end

  # Raised when the TV returns an error response to a request, or sends back a
  # payload we cannot parse.
  class ResponseError < Error
  end

  # Raised when a request does not receive a response within the configured
  # timeout.
  class TimeoutError < Error
  end
end

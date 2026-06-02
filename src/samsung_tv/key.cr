module SamsungTV
  # Remote-control key codes understood by the Samsung "samsung.remote.control"
  # websocket channel. These are sent as the `DataOfCmd` field of a
  # `SendRemoteKey` command (see `Connection#send_key`).
  #
  # Only the keys relevant to this library plus a handful of common navigation
  # keys are defined. The TV accepts many more; any string may be passed to
  # `Client#send_key` directly if needed.
  module Key
    # Power. A short click toggles between "on" and art mode on a Frame TV; a
    # ~3 second hold powers the panel fully off.
    POWER = "KEY_POWER"

    # Volume / mute. These are relative — there is no absolute set over this
    # channel. When audio is routed over HDMI eARC the TV forwards the
    # equivalent CEC command to the external amplifier, so they still work.
    VOLUME_UP   = "KEY_VOLUP"
    VOLUME_DOWN = "KEY_VOLDOWN"
    MUTE        = "KEY_MUTE"

    # Media transport. These drive whatever is currently playing on screen
    # (an app's player, USB media, ...); they have no effect when nothing is
    # playing. Samsung exposes dedicated Play and Pause keys (no single toggle).
    PLAY         = "KEY_PLAY"
    PAUSE        = "KEY_PAUSE"
    STOP         = "KEY_STOP"
    FAST_FORWARD = "KEY_FF"
    REWIND       = "KEY_REWIND"

    # Navigation / menu (handy for callers driving the UI directly).
    HOME   = "KEY_HOME"
    MENU   = "KEY_MENU"
    SOURCE = "KEY_SOURCE"
    UP     = "KEY_UP"
    DOWN   = "KEY_DOWN"
    LEFT   = "KEY_LEFT"
    RIGHT  = "KEY_RIGHT"
    ENTER  = "KEY_ENTER"
    BACK   = "KEY_RETURN"
  end
end

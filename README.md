# samsung_tv

A small **local-only** Crystal library to monitor and control a **Samsung Frame TV**
over its network API (the modern Tizen websocket + REST protocol). No cloud /
SmartThings dependency.

It focuses on the controls that matter:

- **Power** — `On` / `Off`, with state feedback and control.
- **Volume** up/down and **mute** — these work whether the TV uses its own
  speakers or an external amplifier over **HDMI eARC**, because the TV forwards
  the equivalent CEC command when you send a volume/mute key.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     samsung_tv:
       github: your-github-user/samsung_tv
   ```

2. Run `shards install`

## Usage

```crystal
require "samsung_tv"

# Port 8002 (TLS + token auth) is the default for modern TVs.
# Persisting the token to a file means you only pair once.
tv = SamsungTV::Client.new("192.168.1.40", token_file: "/var/lib/tv.token")

# --- status ---
tv.power_state # => SamsungTV::PowerState::On | Off
tv.on?         # => true
tv.frame_tv?   # => true
tv.device_info # => SamsungTV::DeviceInfo (model, mac, ...)

# --- power ---
tv.power_off   # screen off (standby)
tv.power_on    # back on (Wake-on-LAN if it has left the network)
tv.power_state = SamsungTV::PowerState::Off

# --- volume / mute ---
tv.volume_up(3)
tv.volume_down
tv.mute        # toggles mute

# --- media transport (drives whatever is playing on screen) ---
tv.play
tv.pause
tv.stop
tv.fast_forward
tv.rewind

# --- raw remote keys ---
tv.send_key(SamsungTV::Key::HOME)

tv.close
```

### Pairing (first connection)

The first time you connect to a modern TV (port 8002) it shows an
**Allow / Deny** prompt and the connection raises `SamsungTV::UnauthorizedError`.
Accept on the TV, then reconnect — the TV hands back a token, which is stored in
`token_file` (if given) and reused silently afterwards.

### Power model

| State | `PowerState` | Notes |
|-------|--------------|-------|
| `On`  | `"on"` | A normal source **or** art mode (see below) |
| `Off` | `"standby"`, `""`, missing, or unreachable | Screen off; the TV usually stays on the network in standby |

- **Turning off** a Frame TV needs a *held* power key. This firmware only honours
  a hold sent as a stream of `Press` frames — a single Press→Release just toggles
  art mode — so `power_off` sends repeated `Press` frames (`power_off_hold`,
  default 4 s) then a `Release`. On a non-Frame TV a single click is used.
- **Turning on** sends `KEY_POWER` (the TV is reachable in standby). If the TV
  has dropped off the network entirely, `power_on` falls back to **Wake-on-LAN**,
  so the MAC must be known — pass `mac:` or let the library learn it from device
  info while the TV is reachable.

### Why art mode isn't a separate state

On 2024 Frame TVs (verified against model `24_PTM_FTV_T09`), "art mode" cannot be
detected over the **local** API:

- REST `/api/v2/` reports `PowerState == "on"` in both art mode and a normal
  source — the payloads are byte-identical.
- The art-app websocket (`com.samsung.art-app`) connects but never sends
  `ms.channel.ready`, never answers `get_artmode_status`, and pushes no
  `art_mode_changed` / `go_to_standby` events — even across a real toggle, with
  the remote channel also open.
- The control channel doesn't expose the foreground app, and UPnP only offers
  volume + DLNA transport.

The only thing that reports art mode is the **SmartThings cloud** API, which this
library deliberately does not use. So art mode is treated as `On`.

### Volume / HDMI eARC

Volume and mute are sent as **relative** remote-key presses (`KEY_VOLUP`,
`KEY_VOLDOWN`, `KEY_MUTE`). This works with eARC, but means there is no absolute
volume level to set/read and mute is a toggle (no state read-back).

## Development

- `crystal spec` — runs the suite against an in-process fake TV (no hardware needed).
- `crystal tool format` — format.
- `./bin/ameba` — lint.
- `examples/` — runnable scripts (`status.cr`, `power.cr`, `volume.cr`) that take
  the TV host as an argument.

## Scope

Implemented: On/Off state + control, volume/mute, raw keys, device info, Wake-on-LAN.
Out of scope: art-mode detection (not available locally — see above), legacy
(port 55000) and encrypted (port 8000) TVs, app launching, art-image management,
absolute volume via UPnP, SmartThings / any cloud API.

## Contributing

1. Fork it (<https://github.com/your-github-user/samsung_tv/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Stephen von Takach](https://github.com/your-github-user) - creator and maintainer

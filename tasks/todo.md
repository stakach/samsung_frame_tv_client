# Samsung Frame TV client — todo

Plan: `~/.claude/plans/sleepy-juggling-spring.md`

## Status: DONE — verified against the real TV (192.168.4.39)

Final model: **local-only, On/Off** power + volume/mute. Art mode is treated as
`On` (not locally detectable on 2024 Frames — see `lessons.md` / README).

## Implementation
- [x] `error.cr`, `key.cr`, `power_state.cr` (Off/On), `device_info.cr`
- [x] `rest.cr` — device_info / reachable?
- [x] `connection.cr` — persistent remote-control WebSocket + listener + token capture
- [x] `wol.cr` — Wake-on-LAN magic packet
- [x] `client.cr` — On/Off power, volume/mute, raw keys, hold via repeated Press frames

## Tests (20 examples, all green; hardware-free fake TV)
- [x] device_info parsing
- [x] power_state On (`"on"`) / Off (`"standby"`, `""`, unreachable)
- [x] power_on (KEY_POWER, no-op when on) / power_off (repeated-Press hold; click on non-Frame; no-op when off)
- [x] volume up/down, mute, send_key
- [x] token capture + token_file persistence
- [x] `wol_spec.cr` — magic packet bytes

## Verification
- [x] `crystal spec` — 20 examples, 0 failures
- [x] `crystal tool format` + `./bin/ameba` clean
- [x] Real TV: state read, power_off→standby, power_on→on, volume/mute, pairing + silent reconnect
- [x] README + examples updated

## Review

Reverse-engineered the local protocol for a 2024 Samsung Frame
(`24_PTM_FTV_T09`). Key findings (captured against the real device):

- **Art mode is not locally observable** on this firmware — REST `PowerState`
  is `"on"` for both art and a normal source, and the art-app websocket is inert
  (no `ms.channel.ready`, no `get_artmode_status` reply, no push events on a real
  toggle). `ha-samsungtv-smart` only gets it via the SmartThings cloud, which is
  out of scope. → Power modelled as **On/Off**; art mode == On.
- **Off detection:** `PowerState == "standby"` (screen off, still networked);
  `On iff PowerState == "on"`.
- **Power off** needs a held power key delivered as a *stream* of `Press` frames
  (a lone Press→Release only toggles art mode). **Power on** uses `KEY_POWER`
  (reachable in standby); WoL is the off-network fallback. Toggles are guarded by
  current state.

Architecture: `Client` (public On/Off + volume/mute API) over a persistent
remote-control `Connection` (read-loop fiber, token capture) + `REST`
(device info) + `WakeOnLAN`. Art-mode code was removed once detection proved
impossible locally.

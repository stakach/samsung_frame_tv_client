# Lessons

## Deep standby kills the remote websocket; REST app launch still wakes the TV

After hours in standby the TV still answers REST (and the plaintext 8001
websocket replies instantly), but the secure 8002 remote channel completes the
TCP/TLS/upgrade and then **never sends `ms.channel.connect`** — so `KEY_POWER`
cannot be delivered and `power_on` times out. This was the Matter bridge's
"power off works, power on doesn't" bug. Wake-on-LAN did **not** wake this
WiFi-connected TV. What does work, with no auth and from any standby depth:
`POST /api/v2/applications/org.tizen.browser` (HTTP 200 → panel wakes,
PowerState flips to "on"). `power_on`/`art_mode` now use `wake_panel`:
websocket `KEY_POWER` first, REST app launch on ConnectionError/TimeoutError.

**Debugging trap:** `/tmp` is cleaned overnight — the token file vanished, and a
token-less websocket connect to a screen-off TV also hangs (it cannot show the
Allow prompt), which initially contaminated the deep-standby diagnosis. Keep
test tokens somewhere durable and re-verify assumptions when a test that
"worked yesterday" fails.

## Verify protocol assumptions against real hardware, not just the reference

When reimplementing the `samsung-tv-ws-api` art protocol, the reference always
waits for `ms.channel.ready` on the art-app channel before sending requests. The
real TV (2024 Frame, `24_PTM_FTV_T09` / `QA65LS03DAWXXY`) **never sends
`ms.channel.ready`** — only `ms.channel.connect`. So the original handshake
(requiring ready) timed out every time on real hardware even though all specs
passed against a fake TV that was modelled on the reference's (wrong) behaviour.

**Pattern:** green specs gave false confidence because the fake inherited the
reference's assumptions. Always exercise the real device (or capture real frames)
before declaring a network protocol "done." Fix: complete the handshake on
`ms.channel.connect`.

## Art mode is not locally detectable on 2024 Frame TVs

Exhaustively verified on the bench TV (local-only, no cloud): REST `PowerState`
is identical (`"on"`) in art mode and on; the art-app websocket answers nothing
and pushes no events even across a real toggle (with/without the remote channel
open); the control channel doesn't expose the foreground app; UPnP only has
volume + DLNA. `ha-samsungtv-smart` only differentiates art via the SmartThings
**cloud** API. Conclusion: model power as **On/Off** only; treat art mode as On.

## "Off" on a Frame needs a Press-frame *stream*, not a lone Press→Release

- Fully-off state reports `PowerState == "standby"` (screen off, still on the
  network); on reports `"on"`. So `On iff PowerState == "on"`, else `Off`.
- A single `KEY_POWER` Press→Release (even with a 3–6 s gap) only toggles art
  mode — `PowerState` stays `"on"`. The hardware long-press is only triggered by
  a **continuous stream of `Press` frames** (~every 200 ms for ~4 s) then a
  `Release`. `hold_key` was rewritten to send repeated Press frames.
- `KEY_POWER` (Click) wakes a standby TV; the TV is reachable in standby, so
  Wake-on-LAN is only a fallback for when it has left the network.
- Always guard power toggles with the current state (`return if off?` /
  `return if on?`) — `KEY_POWER` is a toggle, so a blind power-off when already
  off would turn the TV back on.

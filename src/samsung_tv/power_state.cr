module SamsungTV
  # Power state of the TV, as reported by the REST `PowerState` field.
  #
  # On a Frame TV "art mode" is *not* a distinct readable state over the local
  # API — it reports `PowerState == "on"` exactly like a normal source, and the
  # art-app websocket on 2024 models (e.g. `24_PTM_FTV_T09`) exposes no usable
  # status. So we model only the two states the TV actually reports locally:
  #
  # * `On`  — `PowerState == "on"` (a normal source *or* art mode).
  # * `Off` — anything else: `"standby"` (screen off, still networked), an empty
  #   value, the field missing, or the TV unreachable.
  enum PowerState
    Off
    On
  end
end

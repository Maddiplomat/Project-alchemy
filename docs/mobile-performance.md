# Mobile Performance

## Targets

- Minimum gameplay target: 60 FPS on supported phones.
- Preferred gameplay target: 90 FPS on higher-end phones.
- Current runtime caps come from `MobilePerformance`:
  - `high`: 90 FPS
  - `balanced`: 60 FPS
  - `low`: 60 FPS

`balanced` is the default profile on touch or mobile devices. The selected profile persists in `user://mobile_performance.cfg`.

## Runtime Changes

- Build placement polling now runs only while build mode is active.
- HUD touch prompts and weather strip updates are throttled instead of polling every frame.
- Minimap redraws and world marker refreshes now run on timers.
- Rain squalls only process while a squall is active.
- Powered lights only process while disrupted, and they reuse cached light textures.
- Campfire, weather rain, and squall rain particle counts now scale by mobile performance profile.
- Light energy and radial light texture resolution now scale by mobile performance profile.
- Rare weather unlock checks are throttled instead of running every physics frame.

## Asset Audit

- Runtime player art is already using `assets/player/main_character_runtime_sheet.png` at `280x320`.
- The largest sampled asset is `assets/player/main_character_sheet.png` at `1024x559`.
- `assets/player/main_character_sheet.png` is not referenced by runtime scenes, but it is still present in export packing logs and should be excluded or removed in a later export cleanup pass.
- Sampled texture imports currently use `compress/mode=0` with mipmaps disabled. That is acceptable for the current mostly pixel-art UI/world assets, but larger non-pixel textures should be reviewed before adding more mobile content.

## Device Test Checklist

- Travel across biome boundaries for 5 minutes and watch for frame drops or memory growth.
- Fight multiple enemies while rain or squall effects are active.
- Open inventory, journal, crafting, and build mode repeatedly during movement.
- Build and rotate structures in quick succession with the mobile build palette open.
- Leave the app running for a 20-30 minute session and confirm heat and battery drain stay acceptable.
- Save, force-close the app, relaunch, and reload the same slot several times.

## Known Follow-Up

- Existing headless boot still reports save checksum mismatch warnings while reading menu save metadata. That should be resolved before claiming long-session save/load stability is fully verified.
- A player-facing graphics settings screen does not exist yet. The runtime profile hook is in place, but exposing it in the UI should happen in a later settings pass.

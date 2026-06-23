# Project Alchemy

Project Alchemy is a Godot 4 survival-crafting prototype built around furnace processing, chemistry crafting, and a sulfur extraction risk loop.

## Game Loop

1. Gather wood, stone, iron, and water around the starting area.
2. Use the `Furnace` to make charcoal and smelt materials.
3. Use the `ChemBench` to craft progression items such as `rust_bolt`, `distillation_kit`, and `sulfuric_bolt`.
4. Push into higher-risk spaces, especially the `Sulfur Flats`.
5. Extract sulfur with the `distillation_kit`.
6. Manage carrier-risk pressure while bringing sulfur back alive.
7. Convert sulfur into stronger chemistry outputs and repeat the loop with better tools and clearer priorities.

## Controls

| Action | Input |
| --- | --- |
| Move | `WASD` or arrow keys |
| Sprint | `Shift` |
| Interact / open stations | `E` |
| Toggle inventory | `Tab` |
| Toggle discovery journal | `J` |
| Scan | `Q` |
| Campfire process | `R` |
| Select hotbar slot | `1`-`5` |
| Mine / attack / fire equipped projectile | Left click |

The current field inventory is intentionally capped at five active slots.

## How To Run

1. Open the project in Godot 4.6.
2. Import `project.godot` if the project is not already in the launcher.
3. Press `F5` to run the project.
4. The project boots into `MainMenu.tscn`, then into the current playable survival-crafting slice.

If you run from the command line and have Godot on your `PATH`, use:

```bash
godot --path .
```

## Current Branch Policy

Development is currently happening on `main`. Keep `main` playable, land focused changes, and use the current `main` build for internal playtests. Generated macOS metadata such as `.DS_Store` should stay untracked.

## Playtest Goal

The current playtest is meant to answer two questions:

1. Can a new player understand the intended progression without spoken explanation?
2. Which parts of the loop are already strong enough to deepen, and which still need readability or friction reduction first?

The playtest should specifically verify that players can:

- understand that the `Furnace` comes before the `ChemBench`
- recognize sulfur as a special high-risk resource
- infer that the `distillation_kit` matters before a sulfur run
- understand that carrying sulfur is the danger state

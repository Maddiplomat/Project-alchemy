# Project Alchemy

Project Alchemy is a Godot 4 survival-crafting prototype about learning chemistry through base planning. The current slice combines resource gathering, furnace processing, chem bench reactions, weather pressure, volatile storage, and night defense.

The design goal is simple: every major danger should teach a readable base-building answer through play.

## Current Game Loop

1. Gather early materials such as wood, stone, iron, charcoal, water, sulfur, and lithium.
2. Use the furnace to process fuel and metals.
3. Build the chem bench and craft progression tools such as the `distillation_kit`.
4. Push into riskier areas, especially the Sulfur Flats.
5. Bring reactive cargo home and stage it correctly instead of leaving it in the player pack.
6. Expand the base with roofs, storage specialization, heat retention, lights, doors, and traps.
7. Use stronger chemistry outputs and better base planning to support longer expeditions.

## Threats And Base Responses

| Threat | Base response | What the player should learn |
| --- | --- | --- |
| Rain / acid mist | Shelter roof over stations and storage | Uncovered stations slow down or malfunction, and uncovered storage can lose item quality. Roofed work areas survive intact. |
| Night / cold exposure | Campfire plus walled enclosure and doors | Open air loses heat quickly. A closed shelter holds campfire warmth and slows cold buildup. |
| Sulfur / volatile instability | Volatile locker separated from furnaces and campfires | Sulfur near heat can flash and be lost. Distance from heat is part of storage safety. |
| Water-reactive materials | Dry box inside sheltered space | Lithium in wet storage loses charge or spoils. A roofed Dry Box protects it cleanly. |
| Night enemies | Walls, doors, powered lights, electric traps | Enemies are drawn toward base signals such as heat, light, and sulfur. Layout can route them into traps or keep them outside. |
| Long expeditions | Restocked home zone with Dry Box and Volatile Locker ready | Returning with unstable cargo and no planned storage can cost valuable material. Stage the base before leaving. |

## Rain Behavior

Rain is now an active base-readability system, not just a weather label.

- Exposed chem benches run with higher reaction risk and slower chemistry.
- Exposed campfires sputter or go out unless protected by a shelter roof.
- Exposed general storage can lose item quality during rain or acid mist.
- Lithium in wet storage loses charge and can spoil unless it is in a roofed Dry Box.
- The player can become `wet` in rain, which worsens cold buildup and makes reactive chemistry less reliable.
- Natural resource spawn pickups are protected from rain degradation. Rain degradation applies to vulnerable materials after they have been picked up, dropped, or stored improperly.

## Controls

| Action | Input |
| --- | --- |
| Move | `WASD` or arrow keys |
| Sprint | `Shift` |
| Interact / open stations / pick up | `E` |
| Toggle inventory | `Tab` |
| Toggle discovery journal | `J` |
| Scan | `Q` |
| Campfire process | `R` |
| Build mode | `B` |
| Cycle buildable in build mode | `Tab` |
| Rotate selected buildable | `R` |
| Cancel build mode | `Esc` |
| Place buildable | Left click |
| Select hotbar slot | `1`-`5` |
| Mine / attack / fire equipped projectile | Left click |

The current field inventory is intentionally capped at five active slots.

## How To Run

1. Open the project in Godot 4.7.
2. Import `project.godot` if the project is not already in the launcher.
3. Press `F5` to run the project.
4. The project boots into `MainMenu.tscn`, then into the current playable survival-crafting slice.

If Godot is available on your `PATH`, you can also run:

```bash
godot --path .
```

For a quick headless project load check:

```bash
godot --headless --path . --quit
```

## Development Notes

Development is currently happening on `main`. Keep `main` playable, land focused changes, and use the current `main` build for internal playtests. Generated macOS metadata such as `.DS_Store` should stay untracked.

Primary gameplay scripts live in `scripts/`, playable scenes live in `scenes/`, and chemistry/resource definitions live under `data/`.

## Playtest Focus

The current playtest should verify that players can:

- understand that furnace processing comes before chem bench progression
- recognize sulfur and lithium as special handling resources
- infer that shelter roofs protect stations, storage, campfires, and the player from rain pressure
- learn that Dry Boxes and Volatile Lockers solve different material risks
- build night shelter intentionally with walls, doors, and campfire heat
- use powered lights and traps as base-layout tools rather than decorations
- plan a home zone before a long expedition

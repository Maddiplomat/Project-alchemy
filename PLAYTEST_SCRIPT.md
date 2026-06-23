# Project Alchemy Playtest Script

Target session length: 30 to 45 minutes

This script is for the current vertical slice in `main`. It is designed to test progression readability, station understanding, the sulfur run, and whether failure states teach the player anything useful.

## Session Goal

Answer these two questions:

1. Can a new player understand the intended progression without spoken explanation?
2. Which parts of the current loop are strong enough to deepen, and which still need readability or friction reduction first?

## Moderator Setup

Before the player starts:

- Launch the current build from `MainMenu.tscn`.
- Do not explain the furnace, chem bench, sulfur rules, or the `distillation_kit` unless the script explicitly calls for intervention.
- Ask the player to think out loud.
- Capture timestamps for confusion, death, first successful station use, first sulfur pickup, and first return from the sulfur biome.

## Success Signals To Watch

- The player identifies gathering, furnace use, chemistry crafting, and sulfur extraction as one connected loop.
- The player understands that the `Furnace` matters before the `ChemBench`.
- The player recognizes sulfur as a special danger state.
- The player understands that dropping sulfur is a meaningful response to pressure.
- The player can explain why the `distillation_kit` matters.

## Route Overview

Use the route below unless the build breaks badly enough that the session becomes invalid.

### 0 to 5 Minutes: Cold Start

Prompt:
"Start the game and tell me what you think your immediate priorities are."

Observe:

- what the player tries first
- whether they notice gatherable resources
- whether they notice the furnace and chem bench area
- whether they open inventory or journal without prompting

Log:

- first stated goal
- first wrong assumption about progression
- whether they identify any station by purpose

### 5 to 12 Minutes: Starter Resource Loop

Prompt:
"Keep going as if you were trying to make real progress."

Target route:

- gather wood, stone, iron, and water
- interact with nearby stations without explanation
- try to convert raw inputs into something useful

Observe:

- whether the player understands how to interact with each station
- whether they distinguish furnace tasks from chem bench tasks
- whether inventory friction slows learning more than expected

Log:

- time to first `Furnace` interaction
- time to first `ChemBench` interaction
- any moment where the player says they do not know what to craft first

### 12 to 20 Minutes: Furnace Understanding

Prompt:
"Try to make something that feels like progression, not just storage."

Target route:

- produce charcoal
- attempt one smelting or furnace-processing outcome
- evaluate whether the player understands heat, fuel, and output expectations

Observe:

- whether charcoal production makes sense without coaching
- whether failed furnace interactions feel readable
- whether the player understands that furnace output unlocks later goals

Log:

- whether the player can explain what the furnace is for
- whether the player hits any furnace failure or confusion state
- whether the player treats the furnace as optional

### 20 to 28 Minutes: Chem Bench Progression

Prompt:
"Try to make something you believe will open up the map or a new resource."

Target route:

- use the `ChemBench`
- craft at least one chemistry result
- ideally reach or understand the value of the `distillation_kit`

Observe:

- whether the player can infer which recipe matters first
- whether recipe names imply purpose clearly enough
- whether chemistry failure feels arbitrary or educational

Log:

- first crafted chemistry output
- whether the player can explain what `rust_bolt`, `distillation_kit`, or `sulfuric_bolt` is for
- whether they connect the bench to sulfur progression on their own

### 28 to 38 Minutes: Sulfur Flats Run

Prompt:
"Explore outward and look for the next high-value objective."

Target route:

- enter the `Sulfur Flats`
- observe the warning sign, remains, and environmental teaching
- collect sulfur
- react to carrier-risk pressure
- attempt to return alive with sulfur

Observe:

- whether the player notices the biome warning before pickup
- whether they understand that carrying sulfur is the danger state
- whether they know dropping sulfur can cancel pressure
- whether the return trip feels tense in a good way or only punitive

Log:

- whether the player understood sulfur danger before pickup or only after
- whether they dropped sulfur at least once
- whether they survived the return trip
- whether the sulfur loop felt legible enough to repeat

### 38 to 45 Minutes: Failure, Recovery, and Debrief

If the player dies:

- let them read the death presentation without interruption
- ask what they think killed them
- ask what they would do differently next run

If the player survives:

- ask what they think the next major goal is
- ask what recipe or system still feels unclear

Close with:

1. "What did you believe the main goal of the game was?"
2. "When did the furnace make sense to you?"
3. "When did the chem bench make sense to you?"
4. "Did you understand sulfur before or after you picked it up?"
5. "Did the game clearly tell you why you died or failed?"
6. "What felt most confusing or unfinished?"

## Intervention Rules

- Do not explain controls unless the player is blocked by input discovery for more than about 60 seconds.
- Do not explain the sulfur rule before the player encounters the sulfur biome.
- Do not explain the `distillation_kit` unless the player has already seen sulfur and cannot form a hypothesis.
- If the player hard-stalls, give one minimal nudge about immediate objective direction, then return to observation mode.

## What Makes The Session Invalid

Discard the run as a progression read if:

- the build crashes
- the player cannot leave the first area due to a bug
- inventory or station input stops responding
- the sulfur route becomes unreachable due to generation or spawn failure

## Build Check Record

- Date: 2026-06-19
- Headless Godot launch check: passed
- Command: `"/Users/angrydiplomat/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path /Users/angrydiplomat/project-alchemy --quit`
- Result: exit code `0`, engine banner only, no startup errors emitted

## Hazard Audit Record

Production-path audit on 2026-06-19 found:

- `MainMenu.tscn` only routes into `World.tscn`
- `World.tscn` does not reference `scenes/dev` or `scripts/dev`
- the old `TestHazard` scene and script were removed after the audit because they were not referenced anywhere in the production scene path
- HUD debug exports exist in `scripts/HUD.gd`, but they default off and are not overridden in `scenes/UI/HUD.tscn`

Current conclusion:

- no production-scene debug hazards are wired into the playable slice
- no placeholder damage source is wired into the playable slice

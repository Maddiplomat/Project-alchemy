# Project Alchemy Playtest Script

Target session length: 40 to 55 minutes

This script is for the current vertical slice in `main`. It is designed to test progression readability, station understanding, separate expedition-zone teaching, and whether failure states teach the player anything useful.

## Session Goal

Answer these two questions:

1. Can a new player understand the intended progression without spoken explanation?
2. Which parts of the current loop are strong enough to deepen, and which still need readability or friction reduction first?

## Moderator Setup

Before the player starts:

- Launch the current build from `MainMenu.tscn`.
- Do not explain the furnace, chem bench, sulfur rules, sodium rules, mercury rules, or the `distillation_kit` unless the script explicitly calls for intervention.
- Ask the player to think out loud.
- Capture timestamps for confusion, death, first successful station use, first travel interaction, first sulfur pickup, first sodium or mercury pickup, and first successful return from a biome.

## Success Signals To Watch

- The player identifies gathering, furnace use, chemistry crafting, travel, and hazardous return handling as one connected loop.
- The player understands that the `Furnace` matters before the `ChemBench`.
- The player recognizes sulfur, sodium, and mercury as different risk types rather than just different colors of loot.
- The player understands that shelter and storage choices are part of chemistry progression.
- The player notices that failed chemistry now tries to explain itself.

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
- whether the inline message and journal cue are noticed after a failed reaction

Log:

- first crafted chemistry output
- whether the player can explain what `rust_bolt`, `distillation_kit`, `sulfuric_bolt`, or mercury-related outputs are for
- whether they connect the bench to expedition progression on their own

### 28 to 38 Minutes: Sulfur Flats Run

Prompt:
"Explore outward and look for the next high-value objective."

Target route:

- enter `Sulfur Flats`
- observe the warning sign, note, and environmental teaching
- collect sulfur
- react to carrier-risk pressure
- attempt to return alive with sulfur

Observe:

- whether the player notices the biome warning before pickup
- whether they understand that carrying sulfur is the danger state
- whether they know dropping sulfur can cancel pressure
- whether the return trip feels tense in a good way or only punitive
- whether `AcidCrawler` pressure feels readable

Log:

- whether the player understood sulfur danger before pickup or only after
- whether they dropped sulfur at least once
- whether they survived the return trip
- whether the sulfur loop felt legible enough to repeat

### 38 to 48 Minutes: Sodium Shoals Run

Prompt:
"Check the other travel destination and tell me what seems different about it."

Target route:

- enter `Sodium Shoals`
- identify sodium and mercury as different resource cases
- pick up at least one sodium or mercury deposit
- return to the overworld with the resource if possible

Observe:

- whether the player understands that the shoals are not just a second sulfur map
- whether sodium's dry-handling implication is legible
- whether mercury reads as contaminated chemistry material rather than generic ore
- whether the player notices that travel back preserves health and collected inventory

Log:

- first interpretation of what sodium is for
- first interpretation of what mercury is for
- whether the player successfully returned with either resource
- whether the shoals loop felt distinct from sulfur

### 48 to 55 Minutes: Failure, Recovery, and Debrief

If the player dies:

- let them read the death presentation without interruption
- ask what they think killed them
- ask what they would do differently next run

If the player survives:

- ask what they think the next major goal is
- ask what recipe, enemy, or resource still feels unclear

Close with:

1. "What did you believe the main goal of the game was?"
2. "When did the furnace make sense to you?"
3. "When did the chem bench make sense to you?"
4. "Did `Sulfur Flats` and `Sodium Shoals` feel meaningfully different?"
5. "Did the game clearly tell you why you died or failed?"
6. "What felt most confusing or unfinished?"

## Intervention Rules

- Do not explain controls unless the player is blocked by input discovery for more than about 60 seconds.
- Do not explain the sulfur rule before the player encounters `Sulfur Flats`.
- Do not explain sodium or mercury before the player reaches `Sodium Shoals`.
- Do not explain the `distillation_kit` unless the player has already seen sulfur and cannot form a hypothesis.
- If the player hard-stalls, give one minimal nudge about immediate objective direction, then return to observation mode.

## What Makes The Session Invalid

Discard the run as a progression read if:

- the build crashes
- the player cannot leave the first area due to a bug
- inventory or station input stops responding
- travel into either biome fails
- carried inventory or health is not preserved correctly across travel

## Build Check Record

- Date: 2026-07-04
- Headless Godot launch check: passed
- Headless `World.tscn` load check: passed
- Command: `"/Users/angrydiplomat/Downloads/Godot.app/Contents/MacOS/Godot" --headless --path /Users/angrydiplomat/project-alchemy --quit`
- Result: exit code `0`, engine banner only, no startup errors emitted

## Hazard Audit Record

Production-path audit on 2026-07-04 found:

- `MainMenu.tscn` routes into `World.tscn`
- the current production slice includes separate travel destinations for `Sulfur Flats` and `Sodium Shoals`
- local and GitHub `main` were aligned at the time of this audit
- weather, chemistry lesson messaging, and journal unread signaling are wired into the playable slice
- no known placeholder debug hazard is intentionally wired into the production scene path

Current conclusion:

- the playable slice is valid for progression and expedition readability testing
- the main remaining risk is design legibility, not obvious production-path debug contamination

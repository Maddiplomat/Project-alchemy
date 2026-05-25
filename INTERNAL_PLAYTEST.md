# Internal Playtest Brief

## Purpose

This document should reflect the game that is actually in the repo today, not the earlier Prototype 4 planning state.

The current playable slice is a survival-crafting loop with:

- a `Furnace` for smelting and charcoal production
- a `ChemBench` for recipe crafting, including `rust_bolt`, `sulfuric_bolt`, and `distillation_kit`
- inventory drag/drop, slot selection, weight pressure, and held-item feedback
- a `Discovery Journal` that logs chemistry outcomes and environmental notes
- an `IronGolem` encounter near the crafting area
- a `Sulfur Flats` biome with sulfur collection requirements and carrier-risk pressure
- death presentation, retry flow, and cause-of-death readouts

The playtest goal is to answer two questions:

1. Can a new player understand the intended progression without spoken explanation?
2. Which parts of the loop are already strong enough to deepen, and which still need readability or friction reduction first?

## Current Game State

### Core Player Loop

The intended loop appears to be:

1. gather wood, stone, iron, and water
2. use the `Furnace` to produce charcoal and smelting outputs
3. use the `ChemBench` to make tools or munitions
4. travel into higher-risk spaces such as the `Sulfur Flats`
5. collect sulfur with the `distillation_kit`
6. manage carrier risk while escaping with sulfur
7. turn sulfur into stronger chemistry outputs such as `sulfuric_bolt`

This is materially stronger than the old P4 loop because the world now includes a concrete mid-game objective and a risk rule tied to carrying sulfur.

### Systems That Appear Present And Playable

- `Furnace`
  Supports temperature, fuel burn, charcoal conversion, smelting, and furnace explosion failure.
- `ChemBench`
  Supports active recipes, recipe summaries, and stabilization failure states including shrapnel, explosion, and toxic cloud outcomes.
- `Inventory`
  Supports 20 slots, drag splitting, dropping into world, item selection, durability display, and weight feedback.
- `Discovery Journal`
  Opens from HUD, logs chemistry results, and now accepts environmental discoveries such as the sulfur warning note.
- `Sulfur Flats`
  Exists as a generated biome with sulfur spawns, an entrance warning sign, and new environmental teaching props.
- `Carrier Risk`
  Surfaces as HUD warning strip, slot highlighting, and ignition countdown pressure while sulfur is carried.
- `Combat Pressure`
  The `IronGolem` is still part of the world and applies pressure near the work area.
- `Failure And Recovery`
  Death overlay, cause-of-death summary, retry, and main-menu exit are implemented.

## What The Current Playtest Needs To Learn

### 1. Is the progression path understandable without tutorial text?

The strongest version of the game now depends on players inferring:

- the furnace matters before the chem bench matters
- sulfur is a special resource, not just another pickup
- the `distillation_kit` is required for safe sulfur extraction
- carrying sulfur is itself the danger state

If players do not infer those four things on their own, more recipes or more combat will not solve the problem.

### 2. Does the sulfur loop land as the current signature feature?

The sulfur loop is the most distinctive system in the current build. The playtest should verify whether players can understand:

- why the `Sulfur Flats` are dangerous
- why the charred remains and note matter
- why sulfur should be dropped under pressure
- whether the warning countdown gives enough time to make a decision
- whether getting sulfur back out feels tense in a good way or only punitive

If this loop is confusing, Prototype 5 should stay focused on sulfur readability before broadening the chemistry tree.

### 3. Does the chemistry loop have a clear payoff structure?

There are now multiple chemistry outputs, but the player still needs to understand:

- what each station is for
- what they should craft first
- what `rust_bolt`, `distillation_kit`, and `sulfuric_bolt` are good for
- whether failed chemistry feels educational instead of arbitrary

If players can craft but cannot explain why one recipe matters more than another, the system still needs stronger framing.

### 4. Does combat create useful pressure or just noise?

The `IronGolem` should test whether danger meaningfully shapes routing and station use.

We need to observe:

- whether players notice the golem before it attacks
- whether they can distinguish combat danger from sulfur danger
- whether the golem interrupts crafting in a way that adds tension rather than annoyance
- whether its reward or encounter logic justifies its presence in the current loop

If players treat the enemy as irrelevant background clutter, combat should not expand yet.

### 5. Is failure readable enough to support iteration?

There are now several failure sources:

- direct enemy damage
- furnace explosion
- chem bench failure outcomes
- sulfur carrier ignition

The current build only works if players can usually answer:

- what killed me
- what I should have done differently
- whether the recovery cost feels fair

If death is visible but not instructive, recovery still needs another pass.

## Recommended Playtest Tasks

- Ask players to explain what they think the starting priorities are after 2 to 3 minutes.
- Ask players to find and use both the `Furnace` and `ChemBench` without coaching.
- Ask players to produce charcoal and at least one crafted result.
- Ask players to enter the `Sulfur Flats` and describe what they think the biome rule is before interacting with sulfur.
- Ask players to obtain sulfur and return with it alive.
- Ask players to explain what the `distillation_kit` is for.
- Let the `IronGolem` encounter happen naturally before giving combat instructions.
- Ask players to open the `Discovery Journal` and explain what information it is useful for.

## Questions To Ask Testers After The Session

- What did you believe the main goal of the game was?
- When did the `Furnace` make sense to you?
- When did the `ChemBench` make sense to you?
- Did you understand what sulfur does before or after you picked it up?
- Did the warning note and corpse at the `Sulfur Flats` entrance help you understand the risk?
- Did you know when to drop sulfur, and did dropping it feel like a meaningful decision?
- What recipe felt most valuable?
- Did the `Discovery Journal` help you learn, or did it feel optional?
- If you died, did the game clearly tell you why?
- What part of the loop felt most confusing or unfinished?

## Current Strengths

- The game now has a more coherent objective chain than the older P4 build.
- Sulfur introduces a concrete risk/reward loop instead of abstract experimentation only.
- Environmental teaching at the `Sulfur Flats` entrance is the right direction for non-tooltip onboarding.
- The HUD already supports several useful feedback channels: health, held item, weight, sulfur warning, and death cause.
- The `Discovery Journal` is starting to work as a memory aid instead of only a reward banner.

## Improvements Needed

### High Priority

- Clarify crafting order
  The player still needs stronger guidance on what to craft first and why `distillation_kit` matters before sulfur collection.
- Improve station differentiation
  `Furnace` and `ChemBench` functions are clearer than before, but the game still risks asking the player to discover too much through UI reading.
- Make sulfur extraction success criteria clearer
  Players must understand whether the kit is required, consumed, damaged, or merely recommended.
- Tighten carrier-risk feedback
  The warning strip exists, but the exact consequence window and best response may still be too easy to miss under stress.
- Strengthen recipe payoff communication
  `rust_bolt`, `distillation_kit`, and `sulfuric_bolt` need clearer use-case framing so the recipe list feels strategic rather than flat.

### Medium Priority

- Improve biome approach readability
  The warning sign, corpse, and crate note are good cues, but the entrance may still need stronger visual contrast or vent telegraphing.
- Make the `Discovery Journal` more actionable
  It logs information, but players may still not recognize when they should consult it during play.
- Re-evaluate `IronGolem` relevance
  If the enemy does not materially shape decisions around stations or sulfur runs, it should be repositioned, redesigned, or temporarily deemphasized.
- Reduce inventory-management friction
  Drag/drop and quantity splitting are implemented, but the amount of manipulation required during high-risk moments may still be too high.

### Lower Priority Unless The Playtest Flags Them Hard

- Expand chemistry breadth
  The current risk is not lack of content. It is whether the existing content is legible and motivating enough.
- Add more enemies
  Additional enemy types should wait until the current encounter clearly improves the loop.
- Add explicit tutorialization
  The current direction should prefer environmental teaching and stronger affordances before adding heavy tutorial text.

## Success Signals

- Players independently identify charcoal, chemistry, sulfur, and extraction as the main progression chain.
- Players understand the `distillation_kit` without being told directly.
- Players recognize that carrying sulfur is the danger state and know dropping it cancels the risk.
- Players can explain at least one chemistry rule and one sulfur rule after a short session.
- The `Discovery Journal` is opened voluntarily or remembered as useful.
- Death usually leads to a concrete lesson, not just frustration.

## Warning Signals

- Players enter the `Sulfur Flats` without noticing the environmental teaching.
- Players pick up sulfur without understanding why the countdown started.
- Players cannot tell whether they are failing due to combat, chemistry, or carrier risk.
- Players use the `ChemBench` but cannot explain what to craft first.
- Testers ignore the `Discovery Journal` completely or describe it as cosmetic.
- The `IronGolem` is either unnoticed or feels unrelated to player goals.

## Recommendation Bias

The current build should still bias toward readability and payoff clarity over content expansion.

The game now has enough systems to expose the intended fantasy. It does not yet clearly prove that players can read those systems fast enough, connect them into a goal chain, and recover from failure with confidence.

If the next playtest is weak, the right response is probably not more content. It is a focused pass on progression legibility, sulfur-loop communication, and recipe prioritization.

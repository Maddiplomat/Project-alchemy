# Internal Playtest Brief

## Purpose

This document should reflect the game that is actually in the repo today, not an earlier planning state.

The current playable slice is a survival-crafting loop with:

- a `Furnace` for smelting and charcoal production
- a `ChemBench` for crafting, dangerous chemistry outcomes, and inline failure lessons
- a five-slot active field inventory with drag/drop, stack management, weight pressure, and held-item feedback
- a `Discovery Journal` with HUD unread-entry signaling
- separate travel destinations for `Sulfur Flats` and `Sodium Shoals`
- sulfur, sodium, and mercury as distinct expedition resources with different handling rules
- weather pressure, volatile storage pressure, and night-defense pressure
- `IronGolem`, `AcidCrawler`, and `LightSwarmer` threats in the current build
- death presentation, retry flow, and cause-of-death readouts

The playtest goal is to answer two questions:

1. Can a new player understand the intended progression without spoken explanation?
2. Which parts of the loop are already strong enough to deepen, and which still need readability or friction reduction first?

## Current Game State

### Core Player Loop

The intended loop appears to be:

1. gather wood, stone, iron, water, and other nearby starter materials
2. use the `Furnace` to produce charcoal and smelting outputs
3. use the `ChemBench` to make progression tools and combat chemistry
4. travel into separate riskier scenes such as `Sulfur Flats` and `Sodium Shoals`
5. recover sulfur, sodium, and mercury while reading each biome's handling rule
6. bring hazardous cargo back through the travel system with health and inventory state preserved
7. stage that cargo correctly at home using shelter, Dry Boxes, Volatile Lockers, and distance from heat
8. turn recovered materials into stronger chemistry outputs and better base planning

This is materially stronger than the older sulfur-only framing because the build now has two distinct expedition scenes and multiple chemistry resources that teach different storage and failure rules.

### Systems That Appear Present And Playable

- `Furnace`
  Supports temperature, fuel burn, charcoal conversion, smelting, and furnace explosion failure.
- `ChemBench`
  Supports active recipes, recipe summaries, stabilization failure states, and inline danger or waste notes at the moment of failure.
- `Inventory`
  Supports five active field slots, drag/drop, splitting, dropping into the world, held-item display, and weight feedback.
- `Discovery Journal`
  Opens from the HUD, logs chemistry and environmental discoveries, and now has a HUD unread-entry indicator.
- `Sulfur Flats`
  Exists as a separate travel scene with its own trailhead, environmental teaching props, weather unlock pacing, sulfur collection pressure, and two `AcidCrawler` enemies.
- `Sodium Shoals`
  Exists as a separate travel scene with sodium crust deposits, exposed mercury spawns, contaminated sediment storytelling, and return travel that preserves expedition state.
- `Carrier Risk`
  Surfaces as HUD warning strip, slot highlighting, ignition countdown pressure, and hazardous outcomes for reactive cargo.
- `Combat Pressure`
  `IronGolem` remains part of the base area pressure, while `LightSwarmer` adds a specific counter-pressure against over-reliance on powered lights.
- `Failure And Recovery`
  Death overlay, cause-of-death summary, retry, main-menu exit, and clearer chemistry failure messaging are implemented.

## What The Current Playtest Needs To Learn

### 1. Is the progression path understandable without tutorial text?

The strongest version of the game now depends on players inferring:

- the furnace matters before the chem bench matters
- expedition travel is the next step after basic station understanding
- sulfur, sodium, and mercury are not interchangeable pickups
- shelter and storage are part of chemistry progression, not side systems
- dangerous chemistry outcomes are meant to teach, not just punish

If players do not infer those things on their own, adding more content will not solve the actual problem.

### 2. Do the two expedition zones teach different rules clearly?

The build now has two separate biome lessons:

- `Sulfur Flats` should teach hazard telegraphing, sulfur recovery pressure, and weather escalation
- `Sodium Shoals` should teach dry handling for sodium and toxic contamination logic for mercury

The playtest should verify whether players can understand:

- why `Sulfur Flats` and `Sodium Shoals` feel different
- whether each travel point reads as a meaningful destination
- whether sulfur, sodium, and mercury communicate their danger before or immediately after pickup
- whether returning from an expedition feels tense in a good way rather than buggy or arbitrary

If both zones collapse into "just another pickup map," the expedition layer still needs readability work.

### 3. Does the chemistry loop have a clear payoff structure?

There are now multiple chemistry outputs and multiple hazardous ingredients, but the player still needs to understand:

- what each station is for
- what they should craft first
- what `distillation_kit`, sulfur outputs, and mercury chemistry are good for
- whether failed chemistry feels educational instead of arbitrary
- whether the inline bench message and journal indicator actually improve learning

If players can craft but cannot explain why one recipe or ingredient matters more than another, the system still needs stronger framing.

### 4. Does combat create useful pressure or just noise?

Combat now has more than one job:

- `IronGolem` pressures the base-adjacent early loop
- `AcidCrawler` pressures Sulfur Flats traversal
- `LightSwarmer` should punish a specific defensive choice instead of acting like a generic enemy

We need to observe:

- whether players notice enemy intent before damage happens
- whether they can distinguish combat danger from chemistry danger and weather danger
- whether `LightSwarmer` pressure makes powered lights feel strategically risky instead of merely decorative
- whether enemy placement adds tension rather than annoyance

If players treat the enemies as unrelated noise, combat should not expand yet.

### 5. Is failure readable enough to support iteration?

There are now several failure sources:

- direct enemy damage
- furnace explosion
- chem bench failure outcomes
- sulfur carrier ignition
- toxic outcomes involving contaminated materials
- weather misuse and bad storage decisions

The current build only works if players can usually answer:

- what killed me or ruined the result
- what I should have done differently
- whether the recovery cost feels fair

If failure is visible but not instructive, readability still needs another pass.

## Recommended Playtest Tasks

- Ask players to explain what they think the starting priorities are after 2 to 3 minutes.
- Ask players to find and use both the `Furnace` and `ChemBench` without coaching.
- Ask players to produce charcoal and at least one crafted result.
- Ask players to enter `Sulfur Flats` and describe what they think the biome rule is before interacting with sulfur.
- Ask players to obtain sulfur and return with it alive if possible.
- Ask players to enter `Sodium Shoals` and explain what they think sodium and mercury are asking them to do differently.
- Ask players to return from a shoals run with at least one hazardous resource.
- Let enemy encounters happen naturally before giving combat instructions.
- Ask players to open the `Discovery Journal` and explain what information it is useful for after a chemistry failure or biome discovery.

## Questions To Ask Testers After The Session

- What did you believe the main goal of the game was?
- When did the `Furnace` make sense to you?
- When did the `ChemBench` make sense to you?
- Did `Sulfur Flats` and `Sodium Shoals` feel meaningfully different?
- Did you understand sulfur before or after you picked it up?
- Did you understand what mercury or sodium were asking you to do differently?
- Did the bench failure text and journal cue help you learn, or did they feel ignorable?
- What recipe or resource felt most valuable?
- If you died or lost a result, did the game clearly tell you why?
- What part of the loop felt most confusing or unfinished?

## Current Strengths

- The game now has a stronger objective chain than the older single-biome framing.
- Separate travel scenes make expeditions feel more intentional than overworld corner zones.
- Sodium, mercury, and sulfur teach different handling rules instead of repeating the same lesson.
- Environmental teaching around travel entrances and contamination props is the right direction for non-tooltip onboarding.
- The HUD now supports several useful feedback channels: health, held item, weight, danger warnings, death cause, and journal unread state.
- Chemistry failure messaging is more actionable now that the authored explanation appears immediately.

## Improvements Needed

### High Priority

- Clarify crafting order
  The player still needs stronger guidance on what to craft first and why certain recipes matter before expeditions.
- Strengthen zone-role readability
  `Sulfur Flats` and `Sodium Shoals` should be understood as distinct lessons, not just distinct maps.
- Make hazardous-resource handling clearer
  Players must understand the difference between volatile storage, dry storage, toxic handling, and simple inventory carrying.
- Tighten enemy signaling
  `LightSwarmer` in particular only works if its attraction to powered light is legible in play.
- Strengthen recipe payoff communication
  Sulfur and mercury outputs need clearer use-case framing so the recipe list feels strategic rather than flat.

### Medium Priority

- Improve expedition approach readability
  Trailheads and warning props are good cues, but the transition from base safety to biome rule may still need stronger telegraphing.
- Make the `Discovery Journal` more actionable
  The unread indicator helps, but players may still not recognize when the journal is worth opening.
- Re-evaluate `IronGolem` relevance
  If it does not materially shape the current route, it should be repositioned, redesigned, or deemphasized.
- Reduce inventory-management friction
  Hazardous return trips can still expose too much manipulation overhead at stressful moments.

### Lower Priority Unless The Playtest Flags Them Hard

- Expand chemistry breadth
  The current risk is not lack of content. It is whether the existing content is legible and motivating enough.
- Add more enemies
  Additional enemy types should wait until the current encounter mix clearly improves the loop.
- Add explicit tutorialization
  The current direction should prefer environmental teaching and stronger affordances before heavier tutorial text.

## Success Signals

- Players independently identify furnace use, chemistry, travel, and hazardous return handling as one connected progression chain.
- Players can explain at least one distinct lesson from `Sulfur Flats` and one from `Sodium Shoals`.
- Players understand that sodium and lithium demand dry handling.
- Players recognize that mercury is a contaminated chemistry resource rather than just generic ore.
- Players notice the chemistry failure explanation or the journal cue without being pushed hard.
- Death or failed chemistry usually leads to a concrete lesson, not just frustration.

## Warning Signals

- Players do not notice that `Sulfur Flats` and `Sodium Shoals` are separate destination choices.
- Players return from travel with the wrong lesson about sodium, mercury, or sulfur.
- Players cannot tell whether they are failing due to combat, chemistry, weather, or carrier risk.
- Players use the `ChemBench` but still cannot explain what to craft first.
- Testers ignore the `Discovery Journal` completely even after the unread cue appears.
- `LightSwarmer` pressure is either unnoticed or feels unrelated to the player's defense choice.

## Recommendation Bias

The current build should still bias toward readability and payoff clarity over content expansion.

The game now has enough systems to expose the intended fantasy. It does not yet clearly prove that players can read those systems fast enough, connect them into a goal chain, and recover from failure with confidence.

If the next playtest is weak, the right response is probably not more content. It is a focused pass on progression legibility, expedition-zone differentiation, hazardous-resource communication, and recipe prioritization.

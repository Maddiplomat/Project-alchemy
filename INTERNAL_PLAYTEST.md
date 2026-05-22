# v0.1.0-proto2 Playtest Brief

## Focus For This Pass

- Test whether over-capacity pressure changes movement and decision-making enough to matter.
- Test whether crafting is discoverable from the current UI without external explanation.
- Confirm that failure state work now has a clear place in the prototype roadmap before chemistry hazards escalate.

## Playtest Questions

### 1. Does over-capacity feel punishing enough?

- Current read: not yet.
- The slowdown is noticeable, but it does not consistently force a hard choice between keeping loot and staying safe.
- Because the penalty is mostly movement speed, the player can still tolerate being overloaded for too long without a strong sense of risk.

### 2. Is crafting discoverable without instructions?

- Current read: partially, but not reliably.
- Players who open the inventory and inspect the panel can find crafting.
- Players who do not press `Tab` or who do not read the full inventory layout may miss it completely.
- The system is present, but the route into it still depends too much on curiosity.

## What Worked

- Health now has consequence. Hazard damage creates tension and supports the next failure-state layer.
- Inventory slot selection and held-item clarity are solid enough to support more mechanics.
- The crafting panel establishes the right direction for Prototype 3 even if onboarding is still thin.

## What Did Not Land Hard Enough

- Over-capacity friction is soft. It inconveniences the player more than it pressures them.
- Crafting lacks an obvious first-use invitation.
- Death handling exists conceptually in the roadmap, but it needs visible presentation and a recovery loop to make failure readable during playtests.

## Upgrade Targets

- Increase over-capacity stakes with either steeper slowdown, stamina-style pressure, drop-risk, or direct hazard vulnerability while overloaded.
- Add one explicit crafting affordance: prompt text, first-time highlight, or contextual hint near the inventory panel.
- Make failure state unmistakable with a death overlay, retry flow, and reset loop that supports repeated chemistry hazard testing.
- Keep the next pass focused on readability over breadth. Prototype 3 needs clear loops more than new systems.

## Recommended Next Questions

- At what inventory threshold does the player start making different choices instead of simply tolerating slowdown?
- Do players understand that held items plus the crafting panel imply combination mechanics?
- Once chemistry explosions arrive, does death feel fair, legible, and fast to recover from?

# Prototype 3 Additions

## Changes & Additions

### 1. Discovery Unlock Notification (UI & Feedback)
- **New Signal**: Added `new_discovery` signal to `DiscoveryLog.gd` to broadcast successful and failed experiments, with tracking for first-time discoveries.
- **Toast UI**: Created `NotificationToast` scene and script. This panel slides in from the top-centre when a discovery is made.
- **Dynamic Messaging**: 
  - Successfully making Steel triggers: `[DISCOVERY UNLOCKED] Steel Alloy`.
  - Carbonising wood for the first time triggers: `[DISCOVERY UNLOCKED] Charcoal — a purer carbon source`.
  - Failed attempts display a quieter `Experiment logged`.
- **Audio Feedback**: Only successful paths play a resonant ding sound effect.

### 2. Lore & Puzzle Hints
- **Blacksmith's Burned Note**: Created a new lore item (`data/lore/blacksmith_note.json`) found in the Blacksmith ruins.
- **Hint Content**: *"…iron holds at twelve hundred…carbon no more than two…the black stone burns cleaner than wood…"*
- **Purpose**: Explicitly guides players on the minimum temperature (1200°C) and carbon ratio (no more than 2) required for the steel reaction. It subtly points toward the necessity of charcoal over standard wood.

### 3. Environmental Storytelling
- **Charcoal Pile Prop**: Created `CharcoalPileProp.tscn`, a non-interactive decoration sprite to be placed near furnace spawn points.
- **Purpose**: Visually signals that charcoal belongs near furnaces, seeding the idea of carbonisation in the player's mind before they've formally discovered the mechanic.

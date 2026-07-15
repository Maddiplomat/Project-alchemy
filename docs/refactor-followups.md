# Refactor Follow-Ups

This file tracks large-script follow-up work after the `FurnaceUI.gd` split.

Rule: do not start these refactors in parallel. Land and stabilize the furnace split pattern first, then use the same collaborator-based approach on the next candidate.

## Guardrails

- Only one large-script split should be active at a time.
- No refactor in this file should intentionally change gameplay, balance, progression pacing, or content behavior.
- If a split requires behavior changes, that work needs a separate gameplay ticket.
- Each split should add or extend focused tests for the extracted logic before the next split starts.

## Ticket RF-001: Split `WorldGen.gd`

Current size: `1967` lines

Problem:
`WorldGen.gd` mixes terrain generation, biome rules, spawn placement, scene restore concerns, and validation in one runtime script.

Target split:

- `WorldGen.gd`
  - scene orchestration, runtime wiring, high-level generation flow
- `WorldTerrainGenerator.gd`
  - terrain layout, tile painting, terrain noise decisions
- `WorldResourcePlacer.gd`
  - resource placement, density rules, placement filtering
- `WorldBiomeRules.gd`
  - biome-specific rules, unlock gates, biome overrides
- `WorldSpawnValidator.gd`
  - spawn safety checks, overlap rules, retry validation

Acceptance:

- World generation output remains stable for the same seed.
- Scene restore and generation still cooperate correctly.
- Placement and validation logic can be exercised without loading the full world scene.

## Ticket RF-002: Split `HUD.gd`

Current size: `989` lines

Problem:
`HUD.gd` owns unrelated UI responsibilities including player status, notifications, journal indicators, objective display, weather strip, and input routing.

Target split:

- `HUD.gd`
  - top-level node wiring, scene references, screen orchestration
- `HUDStatusWidgets.gd`
  - health, weight, held item, day/time, vignette state
- `HUDNotifications.gd`
  - toasts, warning strips, scanner upgrade toast, night defense messaging
- `HUDObjectivesPanel.gd`
  - objective panel content and refresh behavior
- `HUDInputRouter.gd`
  - HUD-owned input paths such as journal/objective toggles

Acceptance:

- HUD display remains visually and behaviorally unchanged.
- Notifications can be triggered without exercising unrelated HUD state.
- Input routing is isolated from status rendering.

## Ticket RF-003: Split `InventoryGrid.gd`

Current size: `966` lines

Problem:
`InventoryGrid.gd` mixes rendering, drag state, slot movement rules, crafting hints, and inventory interaction side effects.

Target split:

- `InventoryGrid.gd`
  - scene wiring, node references, top-level refresh flow
- `InventoryGridRenderer.gd`
  - grid visuals, slot visuals, tooltip display
- `InventoryDragController.gd`
  - drag lifecycle, drag quantity state, drag ghost behavior
- `InventoryMoveRules.gd`
  - slot transfer rules, world drop rules, item placement constraints
- `InventoryCraftingPanel.gd`
  - recipe list state, craftability display, recipe highlight behavior

Acceptance:

- Drag/drop behavior is unchanged.
- Item movement rules can be tested without the full inventory scene.
- Rendering changes stay isolated from inventory mutation logic.

## Ticket RF-004: Split `ChemBenchUI.gd`

Current size: `846` lines

Problem:
`ChemBenchUI.gd` mixes recipe display, ingredient validation, crafting execution, stabilization state, and bench power/status visuals.

Target split:

- `ChemBenchUI.gd`
  - scene orchestration and signal wiring
- `ChemBenchRecipeView.gd`
  - recipe preview, result text, authored feedback
- `ChemBenchSlotController.gd`
  - ingredient slots, validation, movement rules
- `ChemBenchExecution.gd`
  - reaction execution, catalyst consumption, result application
- `ChemBenchVisualState.gd`
  - temperature/power/boost display and bench-specific visual state

Acceptance:

- Bench reaction outcomes and slot behavior do not change.
- Recipe display and execution logic are independently testable.

## Ticket RF-005: Split `ScannerTool.gd`

Current size: `839` lines

Problem:
`ScannerTool.gd` handles scan targeting, result formatting, discovery integration, and visual/audio feedback in one place.

Target split:

- `ScannerTool.gd`
  - tool orchestration and player-facing scan flow
- `ScannerTargeting.gd`
  - hit detection, target filtering, range rules
- `ScannerResultFormatter.gd`
  - result text, scan summary, element formatting
- `ScannerDiscoveryBridge.gd`
  - discovery updates, log integration, research hooks
- `ScannerFeedbackFX.gd`
  - beam/reticle/flash/audio feedback

Acceptance:

- Scan results stay identical for the same targets.
- Discovery updates are isolated from targeting and FX behavior.

## Ticket RF-006: Split `BuildSystem.gd`

Current size: `831` lines

Problem:
`BuildSystem.gd` mixes placement validation, preview rendering, input handling, resource consumption, and final placement.

Target split:

- `BuildSystem.gd`
  - system orchestration and public build-mode entry points
- `BuildPlacementValidator.gd`
  - collision, footprint, biome/base constraints
- `BuildPreviewController.gd`
  - ghost preview rendering, rotate/update behavior
- `BuildCostResolver.gd`
  - resource requirements and consumption checks
- `BuildPlacementExecutor.gd`
  - final placement, persistence export hooks, spawned node setup

Acceptance:

- Build placement rules remain unchanged.
- Preview behavior is isolated from resource spending logic.
- Validation can be tested without full placement execution.

## Ticket RF-007: Split `ResearchObjectives.gd`

Current size: `807` lines

Problem:
`ResearchObjectives.gd` mixes objective definitions, progression mutation, tutorial sequencing, runtime state restoration, and UI-facing notifications.

Target split:

- `ResearchObjectives.gd`
  - orchestration and public objective API
- `ResearchObjectiveData.gd`
  - objective definitions, static descriptors, prerequisite layout
- `ResearchObjectiveProgression.gd`
  - state mutation, completion checks, activation rules
- `ResearchObjectiveNotifications.gd`
  - UI-facing event shaping and toast-ready messaging
- `ResearchTutorialSequencing.gd`
  - tutorial-specific gating and scripted progression beats

Acceptance:

- Objective unlock order and progression remain unchanged.
- Progression and tutorial sequencing can be tested independently.

## Sequencing

Recommended order after the furnace split settles:

1. `InventoryGrid.gd`
2. `HUD.gd`
3. `ChemBenchUI.gd`
4. `BuildSystem.gd`
5. `ScannerTool.gd`
6. `ResearchObjectives.gd`
7. `WorldGen.gd`

Rationale:

- Start with UI-heavy scripts where collaborator seams are already obvious.
- Leave `WorldGen.gd` last because it has the most seed-sensitive runtime behavior and the highest regression risk.

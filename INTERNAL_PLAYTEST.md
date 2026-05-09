# v0.1.0-proto1 Playtest Note

## What felt right

- The seeded forest map reads clearly at a glance, and the spawn clearing gives the first few seconds room to breathe.
- Element pickups are easy to understand: walk up, interact, see the item land in inventory, then inspect it through hover details.
- Inventory drag-and-drop feels direct for a prototype; the ghost icon and swap behavior make slot intent obvious.
- The HUD framing is serviceable already. Health is legible in peripheral vision, and the held-item panel grounds the current state.

## What needs tuning in P2

- Inventory discoverability is still weak. The `Tab` toggle is functional, but the game needs an on-screen prompt or onboarding hint.
- Pickup and movement collision should be tuned together. The smaller player shape helps navigation, but object spacing and interaction radius still need a pass.
- Held-item state needs actual gameplay weight. Right now it displays well, but it should drive use, drop, consume, or tool-specific actions.
- Health is only a shell. P2 should connect damage, healing, feedback, and failure states so the bar carries tension instead of just occupying space.

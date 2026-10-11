# AITycoon

A satirical tycoon/base-building game about running an AI startup. Built with Godot 4 (GDScript).

## Run it
Open Godot, choose **Import**, select this folder's `project.godot`, then press **F5**.

## Controls (prototype)
You start with a small office in the Calizona desert, $2M and two staff who wander around.
- `1`-`8` or the bottom bar: Carpet, Concrete, Wall, Door, Desk, Server Rack, Ficus, Coffee Maker
- Each tile has a 2x2 subgrid. Small items (like the Coffee Maker) snap to a quarter tile, so four fit on one tile
- `X`: Demolish tool (50% refund). Right click also demolishes one tile.
- Left drag: floors fill a box, walls draw a box outline, furniture paints, doors place one at a time
- Right click or `Esc` while dragging: cancel
- `Space`: pause. Speed buttons top right (15 min per quarter at 1x)
- WASD / arrows or middle-drag: pan. Mouse wheel: zoom
- Furniture needs a floor. Staff can only walk on floors and through doors.

## Models
- Name your company when the game starts.
- Server Racks give compute (1 per rack per day). The **Models** tab on the right trains a Small, Medium or Large model; bigger ones take longer and cost more, and each new model builds on your best one.
- When a model ships, users flock to it. Revenue is simply users x $0.05 a day.
- Rival labs (ClosedAI, Gogle, Metta) release models on a fixed script. Falling behind their best model costs you users.

## Staff
- The **Staff** tab hires Researchers, Engineers and Marketers ($5,000 recruiter fee, then a daily salary). Firing costs 5 days of salary.
- Pick each person's job from their dropdown. They walk to a free workstation and get to work (a little busy bubble shows over their head):
  - **Research** at a desk: trains models faster (+25% each).
  - **Engineering** at a server rack: +0.5 compute each.
  - **Growth** at a desk: +20% users each.
  - **Slack off**: wanders around.
- Anyone can do any job, but off-role they work at half speed. No free desk or rack means no work, so build more.

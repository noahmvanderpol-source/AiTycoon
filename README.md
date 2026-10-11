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

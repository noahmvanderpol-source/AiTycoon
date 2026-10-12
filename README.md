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
- When a model ships, users flock to it. Revenue is simply users x $0.055 a day. Hover Revenue in the top bar for the breakdown.
- Rival labs (ClosedAI, Gogle, Metta) release models on a fixed script. Falling behind their best model costs you users.

## Staff
- The **Staff** tab hires Researchers, Engineers, Marketers, Alignment Researchers and Mechanics ($5,000 recruiter fee, then a daily salary). Firing costs 5 days of salary. You start with $150,000. Hover Expenses in the top bar to see what you pay for; below $50,000 and again below $15,000 a warning banner appears.
- Pick each person's job from their dropdown. They walk to a free workstation and get to work (a little busy bubble shows over their head):
  - **Research** at a desk: trains models faster (+25% each).
  - **Engineering** at an Engineer's Workstation (Build > Furniture, $15,000): up to 5 engineers work anywhere within 6 tiles of it, and each tends a server rack in that radius for +0.5 compute. Hover a workstation (or place one) to see its radius and the racks it covers.
  - **Wear and tear:** every rack has a condition from 0 to 100% that scales its output (shown as a bar above the rack once it drops). Racks nobody maintains lose 0.5% a day, down to 25%. Each engineer at a workstation maintains up to 7 racks in its radius and restores 5% a day.
  - **Growth** at a desk: +20% users each.
  - **Maintenance** (Mechanics): stand on floor next to a generator and keep it in shape. Generators have a 0-100% condition that scales what they can make; running ones lose 0.4% a day (less when lightly loaded), down to 25%. Each mechanic restores 4% a day to up to 3 generators within 6 tiles. The starter generator has a gravel strip so a mechanic can reach it.
  - **Slack off**: wanders around, and only collects half their pay.
- Anyone can do any job, but off-role they work at half speed. No free desk or rack means no work, so build more.

## Board
- Every quarter the board sets one target, cycling through: release a model at least as good as the top rival, grow users, and earn revenue. The first quarter only asks you to ship any model.
- At the quarter's end there's a board meeting. Hit the target: +15 Board Confidence. Miss: -25 (-10 in the first quarter).
- **Fired** if Board Confidence hits 0% or your money goes below $0.
- **You win?** when a model reaches capability 100 and replaces you as CEO.
- Click your **company name** in the top bar (or press **O**) to open the **Company page**. Its **Board** tab shows confidence, the current target, progress and days left. The **Policies** tab is a placeholder for company decisions coming later.

## Compute and Deviation
- **Compute** (top bar) comes from racks (heat throttles them) and engineers. Red-Team Rigs eat some first; training gets the rest, sped up by researchers. The Models tab shows the breakdown.
- **Deviation (V)** is how far your AI has drifted from your control. Training adds it (bigger models more, and every model builds on the last), a capable model creeps it up on its own, and **Cut corners** in Models trains on 35% less compute for 2x the Deviation.
- Lower it with **Alignment Researchers** on the Alignment job at a desk, and **Red-Team Rigs** (Build, $40,000, eat 0.5 compute a day). The **Safety theater** blog post buys +5 Board once a quarter and does nothing to Deviation.
- 25%: the AI renames your racks (hover one). 50%: it sabotages rivals for you, but scandals cost Board, rack lights go red and the music turns tense. 75%: it hides a quarter of your compute, writes its own Deviation report and staff quit. 100%: **Takeover**, you lose.
## Power
- Racks draw 6 kW each and AC Units 4 kW. Everything is powered 8 times a day (3 hours a step).
- **Power (P)** opens the power panel and the power build tools. You start with a Portable Generator outside the office.
- Cheapest power runs first: rooftop Solar Panels (2 kW, daytime only), then one Grid Hookup (40 kW cap, $1.20/kWh), then Batteries (200 kWh, charged by spare solar), then generators by fuel price:

| Generator | Output | Fuel | Smog |
| --- | --- | --- | --- |
| Portable Generator ($2,500) | 20 kW | $2.75/kWh | high |
| Diesel Generator ($25,000) | 60 kW | $2.00/kWh | high |
| Large Diesel ($90,000) | 200 kW | $1.40/kWh | high |
| Portable Power Plant ($600,000) | 800 kW | $0.90/kWh | half |

- Generators and the grid hookup go outdoors. Short on power, racks and ACs all run at the share that's covered (a brownout).
- Generators puff smog onto their tile, and it drifts to neighbouring tiles and slowly clears. A faint haze shows always; the Power panel tints it brown.
- Fuel and grid costs are added to your daily expenses.

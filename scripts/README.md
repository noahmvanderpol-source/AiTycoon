# Scripts

The Main node's script is split by system into a chain. Each file `extends` the one before it, so they all share one object: every variable and function is visible everywhere.

state.gd > build.gd > economy.gd > deviation.gd > staff.gd > power.gd > heat.gd > roofs.gd > draw.gd > hover.gd > research_ui.gd > company_ui.gd > ui.gd > tutorial.gd > save.gd > main.gd

- **state.gd**: constants, testing flags (UNLOCK_ALL, INFINITE_MONEY), item tables, all variables.
- **tutorial.gd**: Chet's skippable onboarding tour, offered after the company is named.
- **save.gd**: save/load (JSON in user://saves/), weekly autosave, Game button, Continue on start. Saves every script variable automatically; add per-frame or UI-only vars to SAVE_SKIP.
- **main.gd**: _ready, starter office, _process, input. Attached to scenes/main.tscn.
- Other files: one system each, as named. government.gd, world.gd and music.gd are separate objects.

## Rules for editing
- Edit only the file for your system. Patch the lines you change; don't rewrite whole files.
- New variables and shared constants go in state.gd.
- A file can call functions from earlier files freely. Calling a function defined in a LATER file fails to parse ("Function not found in base self"). Fix: add a stub with the exact same signature under "Forward declarations" at the end of state.gd. Change a stub's signature whenever you change the real one.

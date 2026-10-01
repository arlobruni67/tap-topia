---
name: roblox-command-bar
description: Conventions for adding things to the Tap Topia Roblox game. Use when asked to build, model, add, replace or change anything in the game (parts, NPCs, shops, materials, effects). The game lives in Roblox Studio, not this repo; this repo holds paste-into-Command-Bar Luau scripts.
---

# Adding to the game (Tap Topia)

The place file is NOT in the repo. Every change ships as one Luau script the
user pastes into Studio → View → Command Bar. Don't search the repo for game
code; there is none beyond these folders:

- `retro-studs/`: MaterialService overrides that stud every material.
- `shop-stall/`: striped stall plus a client-animated shopkeeper NPC.

## Layout for a new feature
`<feature>/` (kebab-case) containing:
- `<Feature>_CommandBar.lua`: a header comment with numbered HOW TO USE
  steps, then UPPER_CASE config locals at the top.
- `README.md`: Files / Steps / short notes, same tone as `retro-studs/README.md`.

## Script rules
- Wrap the whole run in `ChangeHistoryService:TryBeginRecording` and finish
  it with Commit on success and Cancel on error (`pcall`), so Ctrl+Z works.
- Make it re-runnable: tag what you build with an attribute and rebuild it in place.
- Never delete the user's stuff. Move replaced models to `ServerStorage` as a backup.
- Find targets via `Selection:Get()` first, then a name config, then auto-find by name.
- Use `Enum.Material.Plastic` for parts so Retro Studs textures them.
- The Command Bar can call `game:GetObjects("rbxassetid://ID")` and set `Script.Source`.
- The Command Bar can't parse multi-line `[[...]]` strings or comments. Use `--`
  comment lines, and embed long code as a table of one-line strings (see `shop-stall/build.py`).
- Strip scripts from inserted free models.
- For NPC animation, embed a `Script` with `RunContext = Client` inside the NPC.
  Drive Motor6D `C0` through springs (see `shop-stall/`) and support both R6 and R15.
- Report results with `print`/`warn` lines prefixed `[FeatureName]`.

## Workflow
Write the files, commit, and push to the session branch. Don't build an artifact
or preview unless asked. Studio can't run here, so say the script is untested in Studio.

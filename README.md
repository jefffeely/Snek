# Snek (Godot Snake Framework)

This workspace now includes a playable Snake framework built with **Godot 4.x** and configured for Windows export.

## Project structure

- `project.godot` - Godot project configuration
- `scenes/Main.tscn` - Main scene
- `scripts/Main.gd` - Core game loop and Snake logic
- `export_presets.cfg` - Windows Desktop export preset
- `build/` - Export output target (`Snek.exe`)

## Gameplay updates

- Board size is `1000x1000` pixels (50x50 grid, 20px cells).
- Every `5` food collected starts a new level.
- Each new level adds more random walls with higher complexity.

## Controls

- `Arrow keys` or `WASD`: Move snake
- `Enter`, `Space`, or `R`: Start/restart game

## Run locally in Godot

1. Install **Godot 4.2+**.
2. Open this folder (`c:\Users\jeffr\Source\Snek`) as a project.
3. Press `F5` to run.

## Export a Windows executable

1. In Godot, install export templates: `Editor -> Manage Export Templates...`
2. Open `Project -> Export...`
3. Select `Windows Desktop` preset.
4. Export to `build\\Snek.exe`.

The result is a standalone Windows executable plus its data file.


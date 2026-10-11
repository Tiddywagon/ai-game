# AI Game

Top-down 3D survival extraction looter shooter built in Godot 4 with GDScript. The design lives in [DESIGN.md](DESIGN.md).

## Run it

1. Install **Godot 4.7** (standard version, not .NET) from https://godotengine.org/download. It's a single program file: unzip it and run it, no installer needed.
2. Get this repo: `git clone https://github.com/Tiddywagon/ai-game.git`, or **Code → Download ZIP** on GitHub.
3. In Godot's Project Manager, click **Import**, select this folder's `project.godot`, then **Import & Edit**.
4. Press **F5** (or the ▶ button, top right) to run. The game starts at the main menu.

## Controls

Play opens a test level for now, with two Scavs and a PMC. You start behind a wall in the south-west corner.

| Key | Action |
|---|---|
| W A S D | Move (relative to the screen) |
| Mouse | Turn to face the cursor |
| Left click | Shoot |
| Right click (hold) | Peek out of cover to aim |
| Space | Combat roll |
| Q | Take / leave cover |
| Shift (hold) | Sprint; uses stamina |
| C | Crouch / stand: slower and quieter |
| Esc | Back to the main menu |

Test-level debug keys: **F1** leg fracture, **F2** overweight, **F3** switch ammo (5.45 PS / BS), **F4** AI on/off.

Roll, cover and bullet numbers live in `data/config/combat.tres`.

## Notes

- Commit the `.uid` files Godot creates next to scripts and scenes; they keep references stable.
- `.godot/` is a local cache and is git-ignored.

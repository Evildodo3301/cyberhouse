# Cyberhouse (Godot 4 project)

Milestone 1 (move, aim, attack on touch), plus swinging doors and the start of
Milestone 2 (the Grunt enemy).
New to Godot? Start with **SETUP.md** in the folder above this one.

## Folder map

```
cyberhouse/
├── project.godot          Project settings (screen size, controls, autoloads)
├── icon.svg               App icon (placeholder)
├── data/                  Tuning numbers you edit in the Inspector, no code
│   ├── player_settings.tres   speed, swing range, aim assist, hit-stop...
│   └── grunt_settings.tres    enemy reaction time (0.2 s), speeds, vision, hearing...
├── scenes/                What you see: things you place and arrange
│   ├── main.tscn              the M1 test room (start here)
│   ├── player/player.tscn     the hitman
│   ├── props/training_dummy.tscn  a target that dies in one hit and respawns
│   ├── weapons/bomb.tscn          thrown bomb: arc, 1 s fuse, blast kills everyone inside
│   ├── ui/touch_controls.tscn     two floating thumbsticks, bomb button, pause button
│   ├── props/swing_door.tscn      push-open door that closes itself, slams knock people down
│   ├── enemies/grunt.tscn         M2 enemy: patrol, see, react, chase, swing, search
│   └── levels/                (empty, real levels go here in M4)
├── scripts/               How things behave (GDScript), same layout as scenes/
│   ├── core/                  game-wide pieces
│   │   ├── game.gd                autoload "Game": restart_room(), hit_stop(), shake(), make_noise(), blood_level
│   │   ├── tactic_tracker.gd      autoload "TacticTracker": logs every kill per room, survives restarts
│   │   ├── player_settings.gd     defines the fields in data/player_settings.tres
│   │   └── game_camera.gd         follow, look-ahead toward aim, screen shake
│   ├── player/player.gd       movement, facing, aim assist, wind-up/strike/recovery
│   ├── ui/virtual_joystick.gd one floating stick (one finger each)
│   ├── ui/bomb_button.gd      fixed button above the aim zone, shows the bomb count
│   ├── ui/touch_controls.gd   turns stick releases into attacks and throws
│   ├── ui/death_screen.gd     red tint + "TAP TO RETRY"
│   ├── weapons/bomb.gd
│   ├── fx/gore_layer.gd       blood and bodies baked into one floor image
│   ├── props/training_dummy.gd
│   ├── levels/main.gd, test_arena.gd
│   ├── props/swing_door.gd
│   └── enemies/grunt.gd, enemy_settings.gd
├── assets/                Art, audio, fonts (empty until M5)
└── tests/m1_smoke_test.gd Automated check that fakes touches (see SETUP.md)
```

## Controls

| | Phone / tablet | PC (for testing) |
|---|---|---|
| Move | Left thumb anywhere on the left half | WASD, or click-drag on the left half |
| Aim | Follows your movement (left stick). Right thumb on the right half overrides it | Arrow keys, or click-drag on the right half |
| Open a door | Walk into it. It swings away from you; slam it into someone to knock them down | Same |
| Attack | Lift the right thumb | Release the mouse on the right half, or Space |
| Attack nearest target | Quick tap on the right half | Quick click on the right half, or Space with no aim |
| Throw bomb | Tap BOMB (goes where you aim or face), or drag from it to pick a direction | Click BOMB, or E |
| Retry after dying | Tap anywhere | Any key or click |
| Cancel an aim | Slide back to the center, then lift | |
| Pause | II button, top left | |
| Restart room | Dying, then tap | R |
| Blood level (full / reduced / off) | (options menu, later) | B |

## Rules the code already follows (so M2 and M3 don't need a rewrite)

- **All tuning numbers live in `data/` Resources**, not inside code. M2 adds `enemy_settings.tres` the same way, so the learning system can change values like vision range without touching enemy code.
- **Anything that can be hit is in the `targets` group and has `is_alive()` and `take_hit(attacker, direction, weapon)`.** The M2 Grunt implements the same two functions, so the player's attack code doesn't change.
- **Every kill sends a death report** to `TacticTracker.report_kill({...})` with weapon, distance, player speed, at_door, chasing_noise. M2 fills in the door and noise fields; M3 adds the "heat" logic inside TacticTracker only.
- **Room memory survives instant restarts.** Restart reloads the scene (fast, well under 0.5 s), which wipes enemies and the room. Memory therefore lives in the `TacticTracker` autoload, filed under each room's `room_id` (set on the room's root node). `clear_room(id)` forgets a room once it's beaten.
- **Kill feedback fires from one place** (`_play_kill_feedback()` in player.gd): hit-stop, directional screen shake and phone vibration happen on the same frame. The M5 hit sound connects to the same `killed_target` signal so it stays in sync.
- **Gore is baked, not spawned.** Each kill paints a body and blood into one floor image the size of the level (`fx/gore_layer.gd`), so the floor fills up without slowing phones down. Kills stay for the whole level and clear on restart. Blood respects `Game.blood_level`.
- **Bombs and enemies use the same hit rules as the player.** The player is in the `player` group and has `is_alive()` / `take_hit()`, so a blast (or an M2 Grunt) kills you the same way it kills a target. Explosions call `Game.make_noise()`, which M2 enemies will "hear".
- **Enemies only know what they sense.** The Grunt sees in a cone with walls and doors blocking sight, hears `Game.make_noise()`, remembers your last known position, and paths around walls with Godot's navigation (doors are left out of the nav map so enemies push through them).
- Placeholder art is drawn by code (`_draw()` functions). In M5 those get swapped for sprites without changing gameplay code.

extends Node
## Global helpers any script can call as `Game.something()`.
## This is an "autoload": Godot creates it once when the game starts and
## keeps it alive across scene changes (see Project Settings > Globals).

## Player option: how much gore to show. FULL is the default. An options menu
## will set this later (and save it); for now press B in the game to cycle it.
enum BloodLevel { FULL, REDUCED, OFF }
var blood_level: BloodLevel = BloodLevel.FULL

## Anything can ask for a screen shake; the camera listens to this.
signal shake_requested(strength: float, direction: Vector2)
## A gunshot: a tiny triple kick on the camera instead of a shake.
signal kick_requested(strength: float, direction: Vector2)
## A gun fired (the void outside the map flashes a neon colour).
signal shot_fired(weapon: WeaponData)
## Someone pushed a door open (enemies in the rooms on either side react).
signal door_opened(door: Node2D, opener: Node2D)
## An enemy died (the room listens to know when it's cleared).
signal enemy_died(enemy: Node2D)
## A loud sound happened at `position`. Enemies (M2) will listen to this to
## "hear" things. `loudness` 1.0 = the whole room hears it.
signal noise_made(position: Vector2, loudness: float)
## A bomb hit the floor and its fuse is burning (enemies that learned BOMB scatter).
signal bomb_landed(position: Vector2, blast_radius: float)


func cycle_blood_level() -> void:
	blood_level = ((blood_level + 1) % BloodLevel.size()) as BloodLevel
	print("Blood level: ", BloodLevel.keys()[blood_level])


func shake(strength: float, direction: Vector2 = Vector2.ZERO) -> void:
	shake_requested.emit(strength, direction)


func kick(strength: float, direction: Vector2) -> void:
	kick_requested.emit(strength, direction)


func make_noise(position: Vector2, loudness: float) -> void:
	noise_made.emit(position, loudness)

## What carries over from one floor of a level to the next: score, combo
## and time. Set when you take the stairs, cleared when a new level starts,
## and kept when you die, so you restart a floor with what you arrived with.
var carried: Dictionary = {}


## Restarts the current room. Reloading a small scene takes well under
## 0.5 s, which is what the design asks for.
func restart_room() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


## Starts another level from scratch (after a level is finished).
func load_level(path: String) -> void:
	carried = {}
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file(path)


## Up (or down) the stairs to another floor of the same level, which is a
## scene of its own: `picture` fills the screen while it loads.
func take_stairs(path: String, picture: Texture2D, carry: Dictionary) -> void:
	carried = carry
	var screen: CanvasLayer = load("res://scripts/ui/loading_screen.gd").new()
	screen.name = "LoadingScreen"
	add_child(screen)
	screen.go(path, picture)


## Freezes the game for a split second to make hits feel heavy.
func hit_stop(duration: float) -> void:
	if duration <= 0.0:
		return
	Engine.time_scale = 0.0
	# The last argument (ignore_time_scale = true) lets this timer keep
	# counting even though we just froze game time.
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0

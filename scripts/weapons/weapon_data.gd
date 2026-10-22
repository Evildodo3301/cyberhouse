class_name WeaponData
extends Resource
## One weapon, described by numbers only. To add a new weapon (machete,
## shotgun...), duplicate a file in res://data/weapons/ and change the values:
## no code needed unless it does something brand new.
##
## Distances are in pixels. One "character width" is 16 px.

enum Kind { MELEE, GUN }

## Short name used in kill reports and the learning system, e.g. "pistol".
@export var id: StringName = &"fists"
## Shown on screen next to the ammo count.
@export var display_name: String = "FISTS"
@export var kind: Kind = Kind.MELEE

@export_group("Reach")
## Melee: how far the swing reaches. Gun: how far a bullet flies before it
## drops (the pistol: 72 px, a third of the screen; fists reach 24). The crosshair sits here.
@export var reach: float = 24.0
## Melee only: how wide the swing is, in degrees.
@export var arc_degrees: float = 90.0

@export_group("Timing")
## Pause before the hit lands (melee) or the shot fires (gun).
@export var windup_time: float = 0.08
## Time after a swing or shot before you can attack again.
@export var recovery_time: float = 0.25

@export_group("Gun")
## Shots in a fresh gun. When it runs dry you drop it and fight with fists.
@export var ammo: int = 0
## How fast bullets fly, in pixels per second (you can see them travel).
@export var bullet_speed: float = 420.0
## Keeps firing while you hold the aim stick (every recovery_time), like
## the machine gun. Off = one shot each time you lift your thumb.
@export var automatic: bool = false
## Bullets per shot (a shotgun would use 5 or more).
@export var pellets: int = 1
## Random spread of each bullet, in degrees either side.
@export var spread_degrees: float = 0.0
## How far the shot is heard: 1 = the whole level, 0 = silent.
@export var noise_loudness: float = 0.0
## Camera kick per shot, in pixels: three jolts in random directions in
## about 0.1 s (a small earthquake). 4 = about 2% of the screen width.
@export var shake: float = 0.0
## How strongly the void outside the map flashes bright on each shot (0 = never, 1 = full).
@export var void_flash: float = 0.0

@export_group("Looks")
## Colour of bullets and of the placeholder shape when there is no art.
@export var color: Color = Color(0.85, 0.85, 0.85)
## Top-down sprite pointing right (+x): lying on the floor and held in hand.
@export var floor_texture: Texture2D
## Side view for the HUD, next to the ammo count.
@export var icon: Texture2D
## Spin frames side by side, played while it flies after a throw.
@export var thrown_texture: Texture2D
@export var thrown_frames: int = 4
## Gun: muzzle fire frames, side by side, pointing right from the barrel.
## Melee: the swing streak.
@export var fire_texture: Texture2D
@export var fire_frames: int = 4
## Frames per second of the fire / swing animation.
@export var fire_fps: float = 60.0
## Arms + weapon drawn on top of the torso, 64 px cells side by side, facing
## up like the body sheets. Frame 0 = holding it; the rest play on an attack
## (melee: wind-up, hit, follow-through; gun: the shot, the recoil).
@export var attack_overlay: Texture2D
## The same for enemies (black-suit sleeves).
@export var enemy_attack_overlay: Texture2D
@export var attack_frames: int = 4
## A star glint runs along the blade now and then, and often while it moves
## (BladeShine). For the machete; a dagger would get it too.
@export var blade_shine: bool = false


## Size to draw the floor sprite at when it's held: never longer than
## HELD_MAX_LENGTH px, so even the machine gun stays smaller than the body
## (about 14 px across the shoulders).
const HELD_MAX_LENGTH := 10.0
const HELD_MAX_SCALE := 0.6


func held_size() -> Vector2:
	if floor_texture == null:
		return Vector2.ZERO
	var size := floor_texture.get_size()
	return size * minf(HELD_MAX_SCALE, HELD_MAX_LENGTH / size.x)


## Frame `index` of a strip of `count` frames laid side by side.
static func frame_rect(texture: Texture2D, count: int, index: int) -> Rect2:
	var w := texture.get_width() / float(count)
	return Rect2(w * clampi(index, 0, count - 1), 0, w, texture.get_height())

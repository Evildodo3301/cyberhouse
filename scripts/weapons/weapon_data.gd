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
## drops (about half the screen for the pistol). The crosshair sits here.
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
## Bullets per shot (a shotgun would use 5 or more).
@export var pellets: int = 1
## Random spread of each bullet, in degrees either side.
@export var spread_degrees: float = 0.0
## How far the shot is heard: 1 = the whole level, 0 = silent.
@export var noise_loudness: float = 0.0
## Screen shake per shot, in pixels.
@export var shake: float = 0.0

@export_group("Looks")
## Colour of the weapon lying on the floor (placeholder until art).
@export var color: Color = Color(0.85, 0.85, 0.85)

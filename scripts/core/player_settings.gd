class_name PlayerSettings
extends Resource
## Every number that controls how the player feels, kept in ONE place.
##
## Why a Resource? You can open res://data/player_settings.tres in the
## Godot editor and tweak these values in the Inspector while you playtest,
## without touching any code. Later, the learning system (M3) can read and
## change values like these in the same way.
##
## Distances are in pixels. One "character width" is 16 px.

@export_group("Movement")
## Top speed. 96 px/s is about 6 character widths per second.
@export var move_speed: float = 96.0
## Seconds to reach top speed. Tiny = snappy, no "ice" feeling.
@export var accel_time: float = 0.05
## Seconds to stop completely after you let go.
@export var stop_time: float = 0.05

@export_group("Melee attack")
## How far the swing reaches (1.5 character widths).
@export var melee_range: float = 24.0
## How wide the swing is, in degrees.
@export var melee_arc_degrees: float = 90.0
## Short pause before the swing hits, so attacks feel committed.
@export var windup_time: float = 0.08
## Time after the swing before you can attack again.
@export var recovery_time: float = 0.25

@export_group("Aim assist")
## If a target is within this many degrees of your aim, the swing snaps to it.
@export var aim_assist_degrees: float = 15.0
## Aim assist only looks this far away.
@export var aim_assist_range: float = 48.0
## A quick tap attacks the nearest target within this radius...
@export var tap_assist_radius: float = 40.0
## ...as long as it is roughly in front of you (degrees either side).
@export var tap_assist_degrees: float = 60.0

@export_group("Bomb")
## Bombs you start each room with (restarting the room refills them).
@export var bombs_per_room: int = 1
## How far a bomb flies (5 character widths), unless a wall stops it first.
@export var bomb_throw_distance: float = 80.0
## How long the bomb is in the air, in seconds.
@export var bomb_flight_time: float = 0.35
## Seconds between landing and exploding.
@export var bomb_fuse_time: float = 1.0
## Everything inside this radius dies, YOU included (2.5 character widths).
@export var bomb_blast_radius: float = 40.0

@export_group("Juice")
## The whole game freezes for this long on a kill ("hit-stop").
@export var hit_stop_time: float = 0.06
## Screen shake strength on a kill, in pixels.
@export var kill_shake: float = 3.0
## Phone vibration on a kill, in milliseconds (0 = off).
@export var kill_vibration_ms: int = 40
## Freeze-frame when the player dies.
@export var death_freeze_time: float = 0.15
## Screen shake strength when the player dies or a bomb goes off.
@export var big_shake: float = 8.0
## Phone vibration when the player dies or a bomb goes off.
@export var big_vibration_ms: int = 120

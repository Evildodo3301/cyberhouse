class_name BloodyFeet
extends RefCounted
## Bloody footprints: step in blood and you leave prints behind you that
## fade out as the blood wears off your soles (Fianso: gone after about
## 10 m of walking). Anyone who walks owns one and calls update() after
## moving: the player, the enemies (shoe prints) and the dogs (paw prints).
##
## The prints are painted into the gore layer, like all blood, so they cost
## nothing to draw and stay for the whole room. Blood setting: FULL = the
## full trail; REDUCED = fainter, and gone in half the distance; OFF = none.

## How far you walk before the blood is gone from your soles, in metres.
const FADE_METRES := 10.0
## Room pixels per metre (a person is 0.5 m = 15 px across the shoulders).
const PX_PER_METRE := 30.0
## Distance between two prints (left, right, left...): one step.
const STEP_PX := 8.0
const PAW_STEP_PX := 6.0
## How dark the first print is (1 = as dark as a pool).
const FIRST_PRINT := 0.8

## Whose feet: "hero", "enemy" (shoe prints) or "dog" (paw prints).
var kind := "hero"
var paws := false

var _blood_left := 0.0   # px of walking before the soles are clean
var _since_step := 0.0
var _left_foot := true
var _gore: GoreLayer


func _init(whose := "hero") -> void:
	kind = whose
	paws = whose == "dog"


## Call after the walker moved by `moved` (room px) to `at`.
func update(walker: Node2D, at: Vector2, moved: Vector2) -> void:
	if Game.blood_level == Game.BloodLevel.OFF or moved == Vector2.ZERO:
		return
	if _gore == null or not is_instance_valid(_gore):
		_gore = walker.get_tree().get_first_node_in_group("gore") as GoreLayer
		if _gore == null:
			return
	var fade_px := _fade_px()
	if _gore.is_bloody(at):
		_blood_left = fade_px   # fresh blood on your soles
		_since_step = 0.0
		return
	if _blood_left <= 0.0:
		return
	_blood_left -= moved.length()
	_since_step += moved.length()
	if _since_step < (PAW_STEP_PX if paws else STEP_PX):
		return
	_since_step = 0.0
	var strength := clampf(_blood_left / fade_px, 0.0, 1.0)
	if Game.blood_level == Game.BloodLevel.REDUCED:
		strength *= 0.6
	var side := moved.normalized().orthogonal() * 2.0 * (-1.0 if _left_foot else 1.0)
	_gore.add_footprint(at + side, moved.angle(), FIRST_PRINT * strength, kind, _left_foot)
	_left_foot = not _left_foot


## True while the soles still leave prints.
func is_wet() -> bool:
	return _blood_left > 0.0


func _fade_px() -> float:
	var px := FADE_METRES * PX_PER_METRE
	return px * 0.5 if Game.blood_level == Game.BloodLevel.REDUCED else px

class_name GameCamera
extends Camera2D
## Follows the player, leans a little toward where they aim, and shakes on kills.
## The view is tilted a few degrees and sways slowly, so the house is never
## square on screen (the player's sticks are turned to match).
## Gunshots use a "kick" instead: three quick jolts in random directions,
## one per frame (about 0.1 s in all, like a small earthquake), with no zoom
## or rotation, so it is over before it can hide anything.

@export var target: Player
## How far (px) the camera leans toward the aim direction.
@export var look_ahead: float = 20.0
## How quickly the lean follows the aim (per second). Smooth, so the camera
## never jumps when you lift your thumb to fire.
@export var look_ahead_speed: float = 5.0
## The lean stays this long after you stop aiming (you fire on release).
@export var look_ahead_hold: float = 0.5
## Tilt of the view in degrees, and how far it sways either side of that.
@export var tilt_degrees: float = 3.0
@export var sway_degrees: float = 1.5
## Seconds for one slow sway back and forth.
@export var sway_seconds: float = 9.0
## How quickly the shake fades (per second).
@export var shake_decay: float = 12.0

var _shake_strength: float = 0.0
var _shake_direction: Vector2 = Vector2.ZERO
## Gunshot kick: the three jolts still to play, and how long the current one lasts.
var _kicks: Array[Vector2] = []
var _kick_time: float = 0.0
var _lean: Vector2 = Vector2.ZERO
var _last_aim: Vector2 = Vector2.ZERO
var _aim_hold: float = 0.0
var _sway_time: float = 0.0
## Each level leans one way or the other.
var _tilt_sign: float = 1.0

## Seconds each of the three kick jolts lasts (one frame at 30 fps).
const KICK_STEP := 0.033


func _ready() -> void:
	ignore_rotation = false
	_tilt_sign = -1.0 if randf() < 0.5 else 1.0
	_update_tilt(0.0)
	Game.shake_requested.connect(shake)
	Game.kick_requested.connect(kick)
	if target:
		global_position = target.global_position
		target.killed_target.connect(_on_kill)


func _process(delta: float) -> void:
	_update_tilt(delta)
	if target:
		# Lean toward the aim. Before, the lean snapped back the instant you
		# lifted your thumb to shoot: a big jump on every shot.
		var aim := target.get_aim_input()
		if aim != Vector2.ZERO:
			_last_aim = aim
			_aim_hold = look_ahead_hold
		else:
			_aim_hold = maxf(_aim_hold - delta, 0.0)
		var want := _last_aim * look_ahead if _aim_hold > 0.0 else Vector2.ZERO
		_lean = _lean.lerp(want, clampf(look_ahead_speed * delta, 0.0, 1.0))
		global_position = target.global_position + _lean
	# Screen shake = an offset that shrinks every frame. Half of it pushes
	# in the hit direction (feels like impact), half is random jitter.
	_shake_strength = lerpf(_shake_strength, 0.0, clampf(shake_decay * delta, 0.0, 1.0))
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1))
	offset = (_shake_direction + jitter) * 0.5 * _shake_strength
	if not _kicks.is_empty():
		offset += _kicks[0]
		_kick_time += delta
		if _kick_time >= KICK_STEP:
			_kick_time = 0.0
			_kicks.pop_front()


## Slow sway round the level's tilt. The player reads its sticks through it.
func _update_tilt(delta: float) -> void:
	_sway_time += delta
	var degrees := _tilt_sign * tilt_degrees + sin(_sway_time * TAU / sway_seconds) * sway_degrees
	rotation = deg_to_rad(degrees)
	if target:
		target.view_rotation = rotation


## Fist kills shake the screen; gun kills only kick it, so a burst of shots
## never turns into a blur.
func _on_kill(_target: Node2D, direction: Vector2) -> void:
	if target.has_gun():
		kick(target.weapon.shake * 1.25, direction)
	else:
		shake(target.settings.kill_shake, direction)


## `direction` is optional: pass the hit direction to push the screen that way.
func shake(strength: float, direction: Vector2 = Vector2.ZERO) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_direction = direction


## Gunshot kick: three jolts of about `strength` pixels, each in a new random
## direction (the first one leans back against the shot), each for KICK_STEP.
func kick(strength: float, direction: Vector2) -> void:
	var back := -direction.normalized() if direction != Vector2.ZERO else Vector2.from_angle(randf() * TAU)
	_kicks = [
		back.rotated(randf_range(-0.6, 0.6)) * strength,
		Vector2.from_angle(randf() * TAU) * strength * 0.8,
		Vector2.from_angle(randf() * TAU) * strength * 0.5,
	]
	_kick_time = 0.0

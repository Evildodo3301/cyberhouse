class_name GameCamera
extends Camera2D
## Follows the player, leans a little toward where they aim, and shakes on kills.
## Gunshots use a "kick" instead: three tiny, very quick jolts (a small
## earthquake) that are over before they can hide anything.

@export var target: Player
## How far (px) the camera leans toward the aim direction.
@export var look_ahead: float = 20.0
## How quickly the shake fades (per second).
@export var shake_decay: float = 12.0

var _shake_strength: float = 0.0
var _shake_direction: Vector2 = Vector2.ZERO
## Gunshot kick: the three jolts still to play, and how long the current one lasts.
var _kicks: Array[Vector2] = []
var _kick_time: float = 0.0

## Seconds each of the three kick jolts lasts (all three: about 0.1 s).
const KICK_STEP := 0.035


func _ready() -> void:
	Game.shake_requested.connect(shake)
	Game.kick_requested.connect(kick)
	if target:
		global_position = target.global_position
		target.killed_target.connect(_on_kill)


func _process(delta: float) -> void:
	if target:
		var aim := target.get_aim_input()
		global_position = target.global_position + aim * look_ahead
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


## Fist kills shake the screen; gun kills only kick it, so a burst of shots
## never turns into a blur.
func _on_kill(_target: Node2D, direction: Vector2) -> void:
	if target.has_gun():
		kick(target.weapon.shake * 1.5, direction)
	else:
		shake(target.settings.kill_shake, direction)


## `direction` is optional: pass the hit direction to push the screen that way.
func shake(strength: float, direction: Vector2 = Vector2.ZERO) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_direction = direction


## Gunshot kick: back against the shot, then sideways, then a smaller push
## back, each for KICK_STEP. `strength` is the first jolt in pixels.
func kick(strength: float, direction: Vector2) -> void:
	var back := -direction.normalized()
	var side := back.orthogonal()
	_kicks = [back * strength, side * strength * 0.6, -back * strength * 0.4]
	_kick_time = 0.0

class_name GameCamera
extends Camera2D
## Follows the player, leans a little toward where they aim, and shakes on kills.

@export var target: Player
## How far (px) the camera leans toward the aim direction.
@export var look_ahead: float = 20.0
## How quickly the shake fades (per second).
@export var shake_decay: float = 12.0

var _shake_strength: float = 0.0
var _shake_direction: Vector2 = Vector2.ZERO


func _ready() -> void:
	Game.shake_requested.connect(shake)
	if target:
		global_position = target.global_position
		target.killed_target.connect(func(_t, dir): shake(target.settings.kill_shake, dir))


func _process(delta: float) -> void:
	if target:
		var aim := target.get_aim_input()
		global_position = target.global_position + aim * look_ahead
	# Screen shake = an offset that shrinks every frame. Half of it pushes
	# in the hit direction (feels like impact), half is random jitter.
	_shake_strength = lerpf(_shake_strength, 0.0, clampf(shake_decay * delta, 0.0, 1.0))
	var jitter := Vector2(randf_range(-1, 1), randf_range(-1, 1))
	offset = (_shake_direction + jitter) * 0.5 * _shake_strength


## `direction` is optional: pass the hit direction to push the screen that way.
func shake(strength: float, direction: Vector2 = Vector2.ZERO) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_direction = direction

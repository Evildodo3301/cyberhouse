class_name WeaponPickup
extends Node2D
## A weapon lying on the floor. Place one in a level, or an enemy drops one
## when it dies (flung a little in the direction it was hit).
## Walk over it with empty hands to pick it up.

@export var weapon: WeaponData
## Shots left in it. -1 = a full gun (weapon.ammo).
@export var ammo: int = -1

var _velocity: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("pickups")
	if ammo < 0 and weapon:
		ammo = weapon.ammo
	if rotation == 0.0:
		rotation = randf() * TAU   # lying at a random angle, like it was dropped


## True if picking it up would give you something to use.
func is_usable() -> bool:
	return weapon != null and (weapon.kind == WeaponData.Kind.MELEE or ammo > 0)


## Throws it across the floor from `from` in `direction`. Walls stop it.
func fling(from: Vector2, direction: Vector2, speed: float = 140.0) -> void:
	global_position = from
	_velocity = direction.normalized() * speed


func _physics_process(delta: float) -> void:
	if _velocity.length() < 2.0:
		_velocity = Vector2.ZERO
	else:
		var step := _velocity * delta
		# Stop at walls (1) and doors (16) instead of sliding through them.
		var query := PhysicsRayQueryParameters2D.create(global_position, global_position + step * 1.5, 1 | 16)
		if get_world_2d().direct_space_state.intersect_ray(query).is_empty():
			global_position += step
			rotation += 12.0 * delta
		else:
			_velocity = Vector2.ZERO
		_velocity = _velocity.move_toward(Vector2.ZERO, 420.0 * delta)
	var player := get_tree().get_first_node_in_group("player")
	if player and player.is_alive() and player.global_position.distance_to(global_position) <= player.settings.pickup_radius:
		if player.try_pick_up(self):
			queue_free()


# Placeholder shape until the Art Director's sprites arrive.
func _draw() -> void:
	if weapon == null:
		return
	var c := weapon.color if is_usable() else weapon.color.darkened(0.6)
	draw_rect(Rect2(-5, -1.5, 10, 3), c)    # barrel
	draw_rect(Rect2(-5, -1.5, 3, 5), c)     # grip

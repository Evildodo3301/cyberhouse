class_name WeaponPickup
extends Node2D
## A weapon lying on the floor. Place one in a level, or an enemy drops one
## when it dies (flung a little in the direction it was hit).
## Walk over it to pick it up (see PlayerSettings.pickup_mode).

@export var weapon: WeaponData
## Shots left in it. -1 = a full gun (weapon.ammo).
@export var ammo: int = -1

## True for the weapon you just swapped away: it waits until you step off it.
var ignore_player: bool = false
## Set when the player throws it: while it flies fast it knocks down the
## first enemy it hits (then bounces off and drops).
var thrower: Node2D
const KNOCK_SPEED := 120.0   # slower than this and it only slides
const HIT_RADIUS := 9.0
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
		if thrower and _velocity.length() >= KNOCK_SPEED:
			_hit_enemy()
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.is_alive():
		return
	var distance: float = player.global_position.distance_to(global_position)
	if ignore_player:
		if distance > player.settings.pickup_radius * 2.0:
			ignore_player = false   # you stepped off: it can be picked up again
		return
	if _velocity == Vector2.ZERO and distance <= player.settings.pickup_radius:
		if player.try_pick_up(self):
			queue_free()


func _hit_enemy() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.is_alive() or not enemy.has_method("knock_down"):
			continue
		if enemy.global_position.distance_to(global_position) > HIT_RADIUS:
			continue
		enemy.knock_down(thrower, _velocity.normalized())
		thrower = null
		_velocity = -_velocity * 0.25   # bounces off and drops at its feet
		return


func _process(_delta: float) -> void:
	if _velocity != Vector2.ZERO:
		queue_redraw()   # the spin frames turn over while it flies


func _draw() -> void:
	if weapon == null:
		return
	var tint := Color.WHITE if is_usable() else Color(0.45, 0.45, 0.45)
	if weapon.thrown_texture and _velocity.length() >= KNOCK_SPEED:
		# Flying after a throw: the spin frames, flat on screen (the node's
		# own spin is undone so the frames do the turning).
		var frame := int(Time.get_ticks_msec() / 50.0) % weapon.thrown_frames
		var rect := WeaponData.frame_rect(weapon.thrown_texture, weapon.thrown_frames, frame)
		draw_set_transform(Vector2.ZERO, -global_rotation)
		draw_texture_rect_region(weapon.thrown_texture, Rect2(-rect.size / 2.0, rect.size), rect, tint)
		draw_set_transform(Vector2.ZERO)
		return
	if weapon.floor_texture:
		var size := weapon.floor_texture.get_size()
		draw_texture(weapon.floor_texture, -size / 2.0, tint)
		return
	# Placeholder shape for a weapon with no art yet.
	var c := weapon.color * tint
	if weapon.kind == WeaponData.Kind.MELEE:
		draw_rect(Rect2(-7, -1, 4, 2.5), Color(0.35, 0.2, 0.1))   # handle
		draw_colored_polygon(PackedVector2Array([Vector2(-3, -1.5), Vector2(7, -1.5), Vector2(9, 0.5), Vector2(-3, 1.5)]), c)   # blade
		return
	draw_rect(Rect2(-5, -1.5, 10, 3), c)    # barrel
	draw_rect(Rect2(-5, -1.5, 3, 5), c)     # grip

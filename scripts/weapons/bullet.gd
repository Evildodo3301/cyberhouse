class_name Bullet
extends Node2D
## A bullet you can see: flies straight at `speed` until it hits a wall, a
## door or a target, or has travelled the weapon's range.

const BODY_RADIUS := 7.0   # how close to a target's centre counts as a hit

var shooter: Node2D
var direction: Vector2 = Vector2.RIGHT
var speed: float = 420.0
var max_distance: float = 100.0
var weapon_id: String = "pistol"
var _travelled: float = 0.0


func fire(from: Vector2, new_direction: Vector2, weapon: WeaponData, new_shooter: Node2D) -> void:
	global_position = from
	direction = new_direction.normalized()
	speed = weapon.bullet_speed
	max_distance = weapon.reach
	weapon_id = String(weapon.id)
	shooter = new_shooter
	rotation = direction.angle()


func _physics_process(delta: float) -> void:
	var step := minf(speed * delta, max_distance - _travelled)
	var from := global_position
	var to := from + direction * step
	var stop := false
	# Walls (1) and doors (16) stop it.
	var wall := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(from, to, 1 | 16))
	if not wall.is_empty():
		to = wall.position
		stop = true
		# A door it hits swings a little way open.
		var door: Node = wall.collider.get_parent()
		if door and door.has_method("nudge"):
			door.nudge(from)
	# The first living target along this step gets hit.
	var target := _first_target(from, to)
	if target:
		global_position = from + direction * (target.global_position - from).dot(direction)
		target.take_hit(shooter, direction, weapon_id)
		if shooter and shooter.has_method("_play_kill_feedback"):
			shooter._play_kill_feedback(target)
		queue_free()
		return
	global_position = to
	_travelled += from.distance_to(to)
	if stop or _travelled >= max_distance - 0.01:
		queue_free()


## Enemy bullets hit the player and fly past other enemies (no friendly fire);
## the player's bullets hit enemies and dummies.
func _first_target(from: Vector2, to: Vector2) -> Node2D:
	var length := from.distance_to(to)
	var best: Node2D = null
	var best_along := INF
	var enemy_shot := shooter != null and shooter.is_in_group("enemies")
	var group := "player" if enemy_shot else "targets"
	for node in get_tree().get_nodes_in_group(group):
		var target := node as Node2D
		if target == null or target == shooter or not target.is_alive():
			continue
		var offset := target.global_position - from
		var along := offset.dot(direction)
		if along < -BODY_RADIUS or along > length + BODY_RADIUS or along >= best_along:
			continue
		if absf(offset.cross(direction)) > BODY_RADIUS:
			continue
		best = target
		best_along = along
	return best


# A short bright streak: the bullet and a little trail behind it.
func _draw() -> void:
	draw_line(Vector2(-6, 0), Vector2.ZERO, Color(1, 0.8, 0.3, 0.5), 1.0)
	draw_line(Vector2(-2, 0), Vector2(1, 0), Color(1, 1, 0.85), 2.0)

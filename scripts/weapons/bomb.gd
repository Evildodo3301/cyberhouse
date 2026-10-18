class_name Bomb
extends Node2D
## A thrown bomb: flies in an arc, lands (or stops at a wall), burns a 1 s
## fuse while showing its blast circle, then kills EVERYTHING inside the
## circle, the player included.

enum State { FLYING, FUSE, EXPLODING }

var settings: PlayerSettings
var thrower: Node2D

var _state: State = State.FLYING
var _from: Vector2
var _to: Vector2
var _timer: float = 0.0
var _height: float = 0.0   # how high above the floor it is drawn, for the arc


## Starts the throw. Called by the player right after adding the bomb to the room.
func throw(from: Vector2, direction: Vector2, new_settings: PlayerSettings, new_thrower: Node2D) -> void:
	settings = new_settings
	thrower = new_thrower
	_from = from
	_to = _landing_point(from, direction)
	global_position = from


## Where the bomb lands: full throw distance, or just before the first wall.
func _landing_point(from: Vector2, direction: Vector2) -> Vector2:
	var end := from + direction * settings.bomb_throw_distance
	var query := PhysicsRayQueryParameters2D.create(from, end, 1 | 16)   # walls and doors
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	if hit:
		return hit.position - direction * 4.0
	return end


func _physics_process(delta: float) -> void:
	_timer += delta
	match _state:
		State.FLYING:
			var t := clampf(_timer / settings.bomb_flight_time, 0.0, 1.0)
			global_position = _from.lerp(_to, t)
			_height = sin(t * PI) * 14.0   # up, then back down
			if t >= 1.0:
				_state = State.FUSE
				_timer = 0.0
				_height = 0.0
				Game.bomb_landed.emit(global_position, settings.bomb_blast_radius)
		State.FUSE:
			if _timer >= settings.bomb_fuse_time:
				_explode()
		State.EXPLODING:
			if _timer >= 0.25:
				queue_free()
	queue_redraw()


func _explode() -> void:
	_state = State.EXPLODING
	_timer = 0.0
	# Kill every target and the player inside the blast.
	var victims := get_tree().get_nodes_in_group("targets") + get_tree().get_nodes_in_group("player")
	for victim in victims:
		if not victim.is_alive():
			continue
		var offset: Vector2 = victim.global_position - global_position
		if offset.length() <= settings.bomb_blast_radius:
			victim.take_hit(thrower, offset.normalized(), "bomb")
	Game.make_noise(global_position, 1.0)   # the whole room hears it (M2)
	Game.shake(settings.big_shake)
	if settings.big_vibration_ms > 0:
		Input.vibrate_handheld(settings.big_vibration_ms)
	Game.hit_stop(settings.hit_stop_time)


func _draw() -> void:
	var red := Color(1.0, 0.2, 0.15)
	match _state:
		State.FLYING:
			draw_circle(Vector2.ZERO, 3.0, Color(0, 0, 0, 0.4))            # shadow
			draw_circle(Vector2(0, -_height), 4.0, Color(0.9, 0.9, 0.9))  # bomb
		State.FUSE:
			# Faint red blast circle, so everyone can see the danger zone.
			draw_circle(Vector2.ZERO, settings.bomb_blast_radius, Color(red, 0.08))
			draw_arc(Vector2.ZERO, settings.bomb_blast_radius, 0.0, TAU, 40, Color(red, 0.5), 1.0)
			draw_circle(Vector2.ZERO, 4.0, Color(0.9, 0.9, 0.9))
			# Blinking light that blinks faster as the fuse runs out.
			var progress := _timer / settings.bomb_fuse_time
			var blink_speed := lerpf(4.0, 16.0, progress)
			if fmod(_timer * blink_speed, 1.0) < 0.5:
				draw_circle(Vector2(0, -3), 2.0, red)
		State.EXPLODING:
			var grow := _timer / 0.25
			draw_circle(Vector2.ZERO, settings.bomb_blast_radius * (0.6 + 0.4 * grow), Color(1.0, 0.8, 0.3, 0.8 * (1.0 - grow)))

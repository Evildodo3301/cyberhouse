class_name SwingDoor
extends Node2D
## A swinging door. Walk into it and it bursts open away from you, then
## swings shut by itself once the doorway is clear, wobbling past closed a
## couple of times like a real saloon-style door. A bullet that hits it
## knocks it a little way open. If it swings into someone
## while it's moving fast, it knocks them down (the classic door-slam move).
##
## Place this node at the hinge. The door panel points along +X, so rotate
## the node to aim the door across the doorway. Enemies (M2) open doors the
## same way the player does, by walking into them.

## Stable ID so the learning system can remember "the door you died in".
## Leave empty to use the node's name.
@export var door_id: String = ""
## Door length in pixels (a doorway is 2.5 character widths).
@export var length: float = 40.0
## How far it swings open, in degrees.
@export var open_angle_degrees: float = 100.0
## Swing speed when pushed open (degrees per second). Fast = slam.
@export var open_speed_degrees: float = 900.0
## Swing speed when closing by itself (degrees per second).
@export var close_speed_degrees: float = 220.0
## Seconds the doorway must be empty before the door starts closing.
@export var close_delay: float = 0.35
## How springy the swing shut is: higher = snappier. With close_damping it
## overshoots closed by about a third, then settles.
@export var close_spring: float = 60.0
@export var close_damping: float = 5.0
## How far a bullet knocks it open, in degrees.
@export var shot_nudge_degrees: float = 22.0
## The door only knocks people down while swinging at least this fast.
@export var knockdown_speed_degrees: float = 400.0
@export var color: Color = Color(0.95, 0.55, 0.15)   # neon orange

## Current angle in degrees (0 = closed, + or - = open to one side).
var angle: float = 0.0
## Degrees per second this frame (for the knockdown check).
var swing_speed: float = 0.0
## Signed degrees per second while it springs shut.
var _spring_velocity: float = 0.0
## Opening speed right now: fast for a push, slow for a bullet nudge (so a
## shot never slams it into anyone).
var _open_speed: float = 900.0

var _target_angle: float = 0.0
var _empty_time: float = 0.0
var _panel: AnimatableBody2D
var _push_zone: Area2D
var _already_hit: Array[Node] = []


## The middle of the doorway, in room coordinates.
func center() -> Vector2:
	return global_position + Vector2.from_angle(global_rotation) * length * 0.5


func _ready() -> void:
	add_to_group("doors")
	if door_id == "":
		door_id = name
	# The solid part: blocks bodies and bullets, layer 5 = "doors".
	_panel = AnimatableBody2D.new()
	_panel.sync_to_physics = false
	_panel.collision_layer = 16
	_panel.collision_mask = 0
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(length, 4.0)
	shape.shape = rect
	shape.position = Vector2(length * 0.5, 0.0)
	_panel.add_child(shape)
	add_child(_panel)
	# The push zone: a slightly wider invisible box around the closed door.
	# Anyone standing in it pushes the door open.
	_push_zone = Area2D.new()
	_push_zone.collision_layer = 0
	_push_zone.collision_mask = 2 | 8   # 2 = player, 8 = enemy bodies
	_push_zone.monitorable = false
	var zone_shape := CollisionShape2D.new()
	var zone_rect := RectangleShape2D.new()
	zone_rect.size = Vector2(length, 26.0)
	zone_shape.shape = zone_rect
	zone_shape.position = Vector2(length * 0.5, 0.0)
	_push_zone.add_child(zone_shape)
	add_child(_push_zone)


func _physics_process(delta: float) -> void:
	var pushers := _push_zone.get_overlapping_bodies()
	if pushers.is_empty():
		_empty_time += delta
		if _empty_time >= close_delay:
			_target_angle = 0.0
	else:
		_empty_time = 0.0
		if is_zero_approx(_target_angle):
			# Open AWAY from whoever pushed: find which side they're on.
			var side := _side_of(pushers[0].global_position)
			_target_angle = -side * open_angle_degrees
			_open_speed = open_speed_degrees
			_already_hit.clear()
			Game.door_opened.emit(self, pushers[0])

	var opening := absf(_target_angle) > absf(angle)
	var new_angle: float
	if opening or not is_zero_approx(_target_angle):
		new_angle = move_toward(angle, _target_angle, _open_speed * delta)
		_spring_velocity = 0.0
	else:
		new_angle = _spring_shut(delta)
	swing_speed = absf(new_angle - angle) / maxf(delta, 0.0001)
	var moving_dir := signf(new_angle - angle)
	angle = new_angle
	_panel.rotation = deg_to_rad(angle)
	if swing_speed >= knockdown_speed_degrees:
		_check_knockdowns(moving_dir)
	queue_redraw()


## Swings back toward closed like a spring, so it overshoots and wobbles.
## Never faster than close_speed_degrees, so closing never knocks anyone down.
func _spring_shut(delta: float) -> float:
	_spring_velocity += (-close_spring * angle - close_damping * _spring_velocity) * delta
	_spring_velocity = clampf(_spring_velocity, -close_speed_degrees, close_speed_degrees)
	var new_angle := angle + _spring_velocity * delta
	if absf(new_angle) < 0.5 and absf(_spring_velocity) < 8.0:
		new_angle = 0.0   # settled
		_spring_velocity = 0.0
	return new_angle


## A bullet hit it: it swings a little way open, away from the shot, then
## shuts again. Called by Bullet. `from` is where the shot came from.
func nudge(from: Vector2) -> void:
	if absf(angle) >= shot_nudge_degrees:
		return   # already open wider than a nudge
	_target_angle = -_side_of(from) * shot_nudge_degrees
	_open_speed = 250.0
	_empty_time = 0.0
	_already_hit.clear()


## +1 or -1 depending on which side of the closed door `pos` is.
func _side_of(pos: Vector2) -> float:
	var local := to_local(pos)
	return 1.0 if local.y >= 0.0 else -1.0


## Anyone the panel sweeps into while moving fast gets knocked down.
func _check_knockdowns(moving_dir: float) -> void:
	var tip_dir := Vector2.from_angle(deg_to_rad(angle))
	# The panel moves along its normal; this is the side it is moving toward.
	var push_dir := tip_dir.orthogonal() * -moving_dir
	var victims := get_tree().get_nodes_in_group("targets") + get_tree().get_nodes_in_group("player")
	for victim in victims:
		if victim in _already_hit or not victim.has_method("knock_down") or not victim.is_alive():
			continue
		var local := to_local(victim.global_position)
		var along := local.dot(tip_dir)
		if along < 4.0 or along > length + 2.0:
			continue
		var across := local.dot(tip_dir.orthogonal()) * -moving_dir
		if across < -2.0 or across > 10.0:
			continue   # not right in front of the moving panel
		_already_hit.append(victim)
		victim.knock_down(self, global_transform.basis_xform(push_dir).normalized())


func _draw() -> void:
	var tip := Vector2.from_angle(deg_to_rad(angle)) * length
	draw_line(Vector2.ZERO, tip, color, 3.0)
	draw_circle(Vector2.ZERO, 2.5, color.lightened(0.3))   # hinge

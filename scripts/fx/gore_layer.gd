class_name GoreLayer
extends Node2D
## Blood and bodies that stay on the floor for the whole room.
##
## Why it's built this way: a node per blood drop would mean thousands of
## nodes after a few kills, which slows phones down. Instead, every splat and
## body is painted ONCE into a single image the size of the room ("baking"),
## and that one image is shown on the floor. 300 kills cost the same to draw
## as 1. Restarting the room reloads the scene, which gives a clean floor.
##
## Anything can add gore with:
##   get_tree().get_first_node_in_group("gore").add_kill(position, direction, color, weapon)

## Respects the player's blood setting (Game.blood_level): FULL, REDUCED
## (a small dark stain, no spray) or OFF (bodies only, no blood).
##
## Size note: this image covers the whole level map, so walking back shows
## every earlier kill. A 3000 x 2000 px map costs about 24 MB of memory, fine
## on phones; much bigger levels will split it into tiles (M4).

## Size of the floor area that can hold gore (match the level size).
@export var area_size: Vector2i = Vector2i(480, 320)
@export var blood_color: Color = Color(0.6, 0.02, 0.08)
@export var dark_blood_color: Color = Color(0.32, 0.0, 0.04)

## How many kills have been painted (used by the test).
var kill_count: int = 0

var _viewport: SubViewport   # an off-screen canvas we paint into
var _painter: Node2D         # draws the new stamps into that canvas
var _pending: Array[Dictionary] = []


func _ready() -> void:
	add_to_group("gore")
	_viewport = SubViewport.new()
	_viewport.size = area_size
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	# Clear the canvas only the very first time, then keep everything painted.
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	# Only re-render when there's something new to paint.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)

	_painter = Node2D.new()
	_painter.draw.connect(_paint_pending)
	_viewport.add_child(_painter)

	var floor_image := Sprite2D.new()
	floor_image.texture = _viewport.get_texture()
	floor_image.centered = false
	add_child(floor_image)


## Paints a kill: a body lying where it fell, a pool under it and blood
## sprayed in the hit direction. A bomb sprays in every direction.
func add_kill(at: Vector2, direction: Vector2, body_color: Color, weapon: String) -> void:
	kill_count += 1
	_pending.append({
		"at": to_local(at),
		"direction": direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT,
		"body_color": body_color,
		"explosive": weapon == "bomb",
	})
	_painter.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Once this frame is drawn, forget the stamps so they're never painted twice.
	if not RenderingServer.frame_post_draw.is_connected(_clear_pending):
		RenderingServer.frame_post_draw.connect(_clear_pending, CONNECT_ONE_SHOT)


func _clear_pending() -> void:
	_pending.clear()
	_painter.queue_redraw()


func _paint_pending() -> void:
	for stamp in _pending:
		match Game.blood_level:
			Game.BloodLevel.FULL:
				_paint_blood(stamp.at, stamp.direction, stamp.explosive)
			Game.BloodLevel.REDUCED:
				_painter.draw_colored_polygon(_blob(stamp.at, 4.0, 6.0), dark_blood_color)
			Game.BloodLevel.OFF:
				pass
		# Torn-apart bodies only at FULL; otherwise a bomb leaves an intact body.
		var torn: bool = stamp.explosive and Game.blood_level == Game.BloodLevel.FULL
		_paint_body(stamp.at, stamp.direction, stamp.body_color, torn)


func _paint_blood(at: Vector2, direction: Vector2, explosive: bool) -> void:
	var spread := PI if explosive else deg_to_rad(35.0)   # how wide the spray is
	var reach := 56.0 if explosive else 40.0
	var drops := 70 if explosive else 40

	# Pool under the body: an uneven blob.
	_painter.draw_colored_polygon(_blob(at + direction * 4.0, 7.0, 11.0), dark_blood_color)

	# Streaks: long smears thrown in the hit direction.
	for i in (6 if explosive else 3):
		var angle := direction.angle() + randf_range(-spread, spread) * 0.6
		var length := randf_range(12.0, reach * 0.8)
		var end := at + Vector2.from_angle(angle) * length
		_painter.draw_line(at, end, blood_color, randf_range(1.5, 3.0))
		_painter.draw_circle(end, randf_range(1.5, 2.5), blood_color)

	# Spray: lots of small drops, denser close to the body.
	for i in drops:
		var angle := direction.angle() + randf_range(-spread, spread)
		var distance := pow(randf(), 1.6) * reach + 3.0
		var color := blood_color if randf() < 0.75 else dark_blood_color
		_painter.draw_circle(at + Vector2.from_angle(angle) * distance, randf_range(0.6, 2.4), color)


## Placeholder body (shapes for now; the Art Director's corpse sprites
## replace this in M5 without changing anything else).
func _paint_body(at: Vector2, direction: Vector2, color: Color, explosive: bool) -> void:
	var lying := color.darkened(0.35)
	_painter.draw_set_transform(at + direction * 6.0, direction.angle())
	if explosive:
		# Torn apart: scattered chunks.
		_painter.draw_set_transform(at, 0.0)
		for i in 5:
			var chunk := Vector2.from_angle(randf() * TAU) * randf_range(4.0, 22.0)
			_painter.draw_circle(chunk, randf_range(1.5, 3.5), lying)
	else:
		_painter.draw_circle(Vector2.ZERO, 5.5, lying)              # torso
		_painter.draw_circle(Vector2(8, 0), 3.5, lying)             # head, thrown back
		_painter.draw_line(Vector2(-2, -3), Vector2(-9, -6), lying, 2.0)  # arm
		_painter.draw_line(Vector2(-2, 3), Vector2(-10, 4), lying, 2.0)   # leg
	_painter.draw_set_transform(Vector2.ZERO, 0.0)


## A random lumpy circle, as a polygon.
func _blob(center: Vector2, min_radius: float, max_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 12:
		points.append(center + Vector2.from_angle(TAU * i / 12.0) * randf_range(min_radius, max_radius))
	return points

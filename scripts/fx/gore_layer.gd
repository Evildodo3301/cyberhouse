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
## How many footprints have been painted, and how dark the last one was (test).
var footprint_count: int = 0
var last_footprint_alpha: float = 0.0

var _viewport: SubViewport   # an off-screen canvas we paint into
var _painter: Node2D         # draws the new stamps into that canvas
var _pending: Array[Dictionary] = []
## Where blood lies on the floor, for bloody footprints (BloodyFeet): the
## WET_CELL px squares that a pool, a splat or a big drop covers.
const WET_CELL := 4
var _wet: Dictionary = {}   # Vector2i -> true


func _ready() -> void:
	add_to_group("gore")
	_viewport = SubViewport.new()
	_viewport.size = area_size
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	# Pixel art stays sharp when bodies are painted in (no blurring).
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
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


## Paints a kill: blood sprayed in the hit direction straight away, then a
## DyingBody plays the next few seconds (legs twitching, spurts from the
## wound, the pool spreading) and hands the body back to finish_kill() to be
## painted for good. A bomb sprays in every direction and, at FULL blood,
## tears the body apart at once (nothing left to twitch).
## `corpse` (optional) paints a sprite instead of the placeholder shapes:
## {"texture": Texture2D, "region": Rect2, "burst_region": Rect2, "scale": float},
## or {"dog": true} for the placeholder doberman.
## The sprite is drawn head-first along `direction`. "burst_region" (a burst
## head) is used for gun and bomb kills when blood is set to FULL.
func add_kill(at: Vector2, direction: Vector2, body_color: Color, weapon: String, corpse: Dictionary = {}) -> void:
	kill_count += 1
	var stamp := {
		"kind": "spray",
		"at": to_local(at),
		"direction": direction.normalized() if direction != Vector2.ZERO else Vector2.RIGHT,
		"explosive": weapon == "bomb",
	}
	var full: bool = Game.blood_level == Game.BloodLevel.FULL
	if stamp.explosive and full:
		stamp.kind = "torn"
		stamp.body_color = body_color
		_queue(stamp)
		return
	_queue(stamp)
	var dying := DyingBody.new()
	dying.name = "DyingBody%d" % kill_count
	dying.gore = self
	dying.at = stamp.at
	dying.direction = stamp.direction
	dying.body_color = body_color
	dying.corpse = corpse
	dying.gory = weapon != "melee" and full
	dying.blood_level = Game.blood_level
	add_child(dying)


## Blood drops from a spurt landing on the floor: [[position, size], ...].
func add_stains(drops: Array) -> void:
	_queue({"kind": "stains", "drops": drops})


## The dying is over: paint its pool and body into the floor for good.
func finish_kill(dying: DyingBody) -> void:
	_queue({
		"kind": "body",
		"pool": dying.pool_polygon(dying.pool_radius()) if dying.pool_radius() > 0.5 else PackedVector2Array(),
		"at": dying.at,
		"direction": dying.direction,
		"body_color": dying.body_color,
		"corpse": dying.corpse,
		"gory": dying.gory,
	})


## A bloody footprint (from BloodyFeet): `alpha` 0..1 fades it out.
func add_footprint(at: Vector2, angle: float, alpha: float, kind: String, left: bool) -> void:
	if alpha <= 0.02:
		return
	footprint_count += 1
	last_footprint_alpha = alpha
	_queue({"kind": "foot", "at": to_local(at), "angle": angle, "alpha": alpha, "kind_of_foot": kind, "left": left})


## True if there's blood on the floor at `at` (someone stepping here gets
## bloody soles): painted blood, or a pool still spreading under a body.
func is_bloody(at: Vector2) -> bool:
	var local := to_local(at)
	if _wet.has(Vector2i((local / WET_CELL).floor())):
		return true
	for child in get_children():
		if child is DyingBody:
			var middle: Vector2 = child.at + child.direction * 4.0
			if local.distance_to(middle) < child.pool_radius() * 0.65:
				return true
	return false


func _mark_wet(center: Vector2, radius: float) -> void:
	var lo := Vector2i(((center - Vector2.ONE * radius) / WET_CELL).floor())
	var hi := Vector2i(((center + Vector2.ONE * radius) / WET_CELL).floor())
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var cell_center := (Vector2(x, y) + Vector2(0.5, 0.5)) * WET_CELL
			if cell_center.distance_to(center) <= radius:
				_wet[Vector2i(x, y)] = true


func _queue(stamp: Dictionary) -> void:
	_pending.append(stamp)
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
		match stamp.kind:
			"spray":
				if Game.blood_level == Game.BloodLevel.FULL:
					_paint_spray(stamp.at, stamp.direction, stamp.explosive)
			"torn":
				_painter.draw_colored_polygon(_blob(stamp.at, 7.0, 11.0), dark_blood_color)
				_mark_wet(stamp.at, 8.0)
				_paint_spray(stamp.at, stamp.direction, true)
				draw_body(_painter, stamp.at, stamp.direction, stamp.body_color, {"torn": true}, true)
			"stains":
				for drop in stamp.drops:
					_painter.draw_circle(drop[0], drop[1], blood_color if randf() < 0.7 else dark_blood_color)
					if drop[1] >= 1.5:
						_mark_wet(drop[0], drop[1])
			"body":
				if stamp.pool.size() > 2:
					_painter.draw_colored_polygon(stamp.pool, dark_blood_color)
					var middle := Vector2.ZERO
					for point in stamp.pool:
						middle += point
					middle /= stamp.pool.size()
					var reach := 0.0
					for point in stamp.pool:
						reach += point.distance_to(middle)
					_mark_wet(middle, reach / stamp.pool.size() * 0.8)
				draw_body(_painter, stamp.at, stamp.direction, stamp.body_color, stamp.corpse, stamp.gory)
			"foot":
				_paint_footprint(stamp)


## Streaks and spray thrown in the hit direction (the pool comes later).
func _paint_spray(at: Vector2, direction: Vector2, explosive: bool) -> void:
	var spread := PI if explosive else deg_to_rad(35.0)   # how wide the spray is
	var reach := 56.0 if explosive else 40.0
	var drops := 70 if explosive else 40

	# Streaks: long smears thrown in the hit direction.
	for i in (6 if explosive else 3):
		var angle := direction.angle() + randf_range(-spread, spread) * 0.6
		var length := randf_range(12.0, reach * 0.8)
		var end := at + Vector2.from_angle(angle) * length
		_painter.draw_line(at, end, blood_color, randf_range(1.5, 3.0))
		_painter.draw_circle(end, randf_range(1.5, 2.5), blood_color)
		_mark_wet(end, 1.5)

	# Spray: lots of small drops, denser close to the body.
	for i in drops:
		var angle := direction.angle() + randf_range(-spread, spread)
		var distance := pow(randf(), 1.6) * reach + 3.0
		var color := blood_color if randf() < 0.75 else dark_blood_color
		var size := randf_range(0.6, 2.4)
		_painter.draw_circle(at + Vector2.from_angle(angle) * distance, size, color)
		if size >= 1.8:
			_mark_wet(at + Vector2.from_angle(angle) * distance, size)


## One footprint: the Art Director's print for that walker (a left shoe or
## a paw, toe down), tinted dark blood, mirrored for the right foot, turned
## the way the walker went.
const FOOTPRINTS := {
	"hero": preload("res://assets/characters/pixel/hero_foot.png"),
	"enemy": preload("res://assets/characters/pixel/enemy_foot.png"),
	"dog": preload("res://assets/characters/pixel/dog_paw.png"),
}


func _paint_footprint(stamp: Dictionary) -> void:
	var color := dark_blood_color.lightened(0.15)
	color.a = stamp.alpha
	var kind: String = stamp.kind_of_foot
	var texture: Texture2D = FOOTPRINTS.get(kind, FOOTPRINTS.hero)
	var size := 0.5   # the Art Director's rule: a shoe print is about 0.27 m
	var flip := 1.0 if stamp.left or kind == "dog" else -1.0
	_painter.draw_set_transform(stamp.at, stamp.angle - PI * 0.5, Vector2(size * flip, size))
	_painter.draw_texture(texture, -texture.get_size() / 2.0, color)
	_painter.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws a body lying on the floor onto `canvas` (the gore image, or a
## DyingBody while it twitches). `legs` bends the legs by that many radians.
static func draw_body(canvas: CanvasItem, at: Vector2, direction: Vector2, color: Color, corpse: Dictionary, gory: bool, legs: float = 0.0) -> void:
	if corpse.get("torn", false):
		_draw_torn(canvas, at, color)
	elif corpse.get("dog", false):
		_draw_dog(canvas, at, direction, legs)
	elif corpse.has("texture"):
		_draw_corpse(canvas, at, direction, corpse, gory, legs)
	else:
		_draw_placeholder(canvas, at, direction, color, legs)


## Placeholder body (shapes for now; the Art Director's corpse sprites
## replace this without changing anything else).
static func _draw_placeholder(canvas: CanvasItem, at: Vector2, direction: Vector2, color: Color, legs: float) -> void:
	var lying := color.darkened(0.35)
	canvas.draw_set_transform(at + direction * 6.0, direction.angle())
	canvas.draw_circle(Vector2.ZERO, 5.5, lying)              # torso
	canvas.draw_circle(Vector2(8, 0), 3.5, lying)             # head, thrown back
	canvas.draw_line(Vector2(-2, -3), Vector2(-9, -6), lying, 2.0)  # arm
	canvas.draw_line(Vector2(-2, 3), Vector2(-2, 3) + Vector2(-8, 1).rotated(legs), lying, 2.0)   # leg
	canvas.draw_set_transform(Vector2.ZERO, 0.0)


## Torn apart by a bomb: scattered chunks.
static func _draw_torn(canvas: CanvasItem, at: Vector2, color: Color) -> void:
	var lying := color.darkened(0.35)
	for i in 5:
		var chunk := Vector2.from_angle(randf() * TAU) * randf_range(4.0, 22.0)
		canvas.draw_circle(at + chunk, randf_range(1.5, 3.5), lying)


## The placeholder doberman, lying on its side with its legs out.
static func _draw_dog(canvas: CanvasItem, at: Vector2, direction: Vector2, legs: float) -> void:
	var coat := Color(0.1, 0.07, 0.06)
	var tan := Color(0.55, 0.33, 0.16)
	canvas.draw_set_transform(at, direction.angle())
	for i in 4:   # legs, sticking out sideways, kicking
		var hip := Vector2(-4.0 + 6.0 * (i % 2), 2.0)
		var kick := legs * (1.0 if i < 2 else -1.0)
		canvas.draw_line(hip, hip + Vector2(0.0, 5.0).rotated(kick), tan, 1.5)
	var body := PackedVector2Array()
	for i in 12:
		body.append(Vector2.from_angle(TAU * i / 12.0) * Vector2(7.0, 3.5))
	canvas.draw_colored_polygon(body, coat)
	canvas.draw_circle(Vector2(8.5, 0.5), 2.6, coat)        # head
	canvas.draw_line(Vector2(10.5, 0.8), Vector2(13.0, 1.4), tan, 1.6)   # snout
	canvas.draw_line(Vector2(-7.0, 0.0), Vector2(-10.5, 1.5), coat, 1.0)  # tail
	canvas.draw_set_transform(Vector2.ZERO, 0.0)


## A corpse sprite. Sheets draw bodies head-up, so turn "up" to the hit
## direction. The lower half (the legs) can be bent a little for the twitch.
static func _draw_corpse(canvas: CanvasItem, at: Vector2, direction: Vector2, corpse: Dictionary, gory: bool, legs: float) -> void:
	var region: Rect2 = corpse.burst_region if gory else corpse.region
	var size: Vector2 = region.size
	var base := Transform2D(direction.angle() + PI * 0.5, at) * Transform2D(0.0, Vector2.ONE * corpse.scale, 0.0, Vector2.ZERO)
	if legs == 0.0:
		canvas.draw_set_transform_matrix(base)
		canvas.draw_texture_rect_region(corpse.texture, Rect2(-size * 0.5, size), region)
	else:
		var half := Vector2(size.x, size.y * 0.5)
		canvas.draw_set_transform_matrix(base)
		canvas.draw_texture_rect_region(corpse.texture, Rect2(-size * 0.5, half), Rect2(region.position, half))
		# Legs: turned about the hips (the middle of the picture).
		canvas.draw_set_transform_matrix(base * Transform2D(legs, Vector2.ZERO))
		canvas.draw_texture_rect_region(corpse.texture, Rect2(Vector2(-size.x * 0.5, 0.0), half), Rect2(region.position + Vector2(0, half.y), half))
	canvas.draw_set_transform(Vector2.ZERO, 0.0)


## A random lumpy circle, as a polygon.
func _blob(center: Vector2, min_radius: float, max_radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 12:
		points.append(center + Vector2.from_angle(TAU * i / 12.0) * randf_range(min_radius, max_radius))
	return points

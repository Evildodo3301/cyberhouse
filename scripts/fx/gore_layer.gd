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
## every earlier kill. It holds DETAIL pixels per room pixel, so the bodies
## painted in keep the people's 1/3 room px pixel art; level 1 (736 x 424
## room px) costs about 11 MB of memory, fine on phones; much bigger levels
## will split it into tiles (M4).

## Size of the floor area that can hold gore (match the level size).
@export var area_size: Vector2i = Vector2i(480, 320)
## Two of the Art Director's six blood reds, so drawn drops match the sheets.
@export var blood_color: Color = Color("#a3141f")
@export var dark_blood_color: Color = Color("#4a070d")

## How many kills have been painted (used by the test).
var kill_count: int = 0
## How many footprints have been painted, and how dark the last one was (test).
var footprint_count: int = 0
var last_footprint_alpha: float = 0.0

## Image pixels per room pixel: as fine as the people's pixel art (1/3).
const DETAIL := 3

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
	_viewport.size = area_size * DETAIL
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
	_painter.scale = Vector2.ONE * DETAIL   # paints in room px
	_painter.draw.connect(_paint_pending)
	_viewport.add_child(_painter)

	var floor_image := Sprite2D.new()
	floor_image.texture = _viewport.get_texture()
	floor_image.centered = false
	floor_image.scale = Vector2.ONE / DETAIL
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
	dying.hit_direction = stamp.direction
	if corpse.has("pixel"):
		corpse = corpse.duplicate()
		var fit := fit_corpse(at, stamp.direction, corpse)
		dying.at = to_local(fit[0])
		dying.direction = fit[1]
		corpse.variant = fit[2]
	dying.body_color = body_color
	dying.corpse = corpse
	dying.gory = weapon != "melee" and full
	dying.blood_level = Game.blood_level
	add_child(dying)


## What a lying body may never be drawn over (Fianso): walls and the strip
## along them, and furniture (its whole drawn shape, tables included).
const CORPSE_BLOCKERS := 1 | 128 | 64 | 256
## Turns tried away from the hit direction, and how far the body may slide.
const FIT_TURNS := [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, PI]
const FIT_SLIDES := [0.0, 4.0, 8.0, 12.0, 16.0]
static var _pose_points: Dictionary = {}   # anim name -> PackedVector2Array


## Where and how a pixel body lies so that no part of it, in any frame of
## its death or its dead pose, covers a wall or furniture: the hit direction
## and its own pose first, then other poses, a little turned, then slid out
## a few px. Returns [position (global), head direction, variant].
func fit_corpse(at: Vector2, direction: Vector2, corpse: Dictionary) -> Array:
	var who: String = corpse.pixel
	var size := float(corpse.get("size", 1.0))
	var variants: Array = [corpse.get("variant", "")]
	for n in ["", "2", "3", "4"]:
		if not variants.has(n) and not HdBody.info_of(who + "_death" + n).is_empty():
			variants.append(n)
	var space := get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = CORPSE_BLOCKERS
	var best := [at, direction, variants[0]]
	var best_hits := 1 << 30
	for slide in FIT_SLIDES:
		for turn in FIT_TURNS:
			var heading := direction.rotated(turn)
			for variant in variants:
				var points := pose_points(who + "_death" + variant, who + "_dead" + variant)
				for shift in ([Vector2.ZERO] if slide == 0.0 else _ring(slide)):
					var hits := 0
					var placed: Vector2 = at + shift
					var turn_by := heading.angle() + PI * 0.5
					for point in points:
						query.position = placed + (point * size).rotated(turn_by)
						if not space.intersect_point(query, 1).is_empty():
							hits += 1
							if hits >= best_hits:
								break
					if hits == 0:
						return [placed, heading, variant]
					if hits < best_hits:
						best_hits = hits
						best = [placed, heading, variant]
	return best


## Eight spots `distance` px around (0, 0).
static func _ring(distance: float) -> Array:
	var spots := []
	for i in 8:
		spots.append(Vector2.from_angle(TAU * i / 8.0) * distance)
	return spots


## The drawn pixels of a death (every frame) and its dead pose, as
## points about 1 room px apart relative to the pivot, at size 1, outermost
## first (so a misfit is found quickly).
static func pose_points(death: String, dead: String) -> PackedVector2Array:
	var key := death + "|" + dead
	if _pose_points.has(key):
		return _pose_points[key]
	var seen := {}
	for name in [death, dead]:
		var info := HdBody.info_of(name)
		if info.is_empty():
			continue
		var image: Image = HdBody._texture(info.file).get_image()
		if image.is_compressed():
			image.decompress()
		var scale := float(info.game_scale)
		var step := maxi(int(round(1.0 / scale)), 1)   # about 1 room px
		var frames: Array = range(int(info.frames))   # every frame: a pose in between can poke out too (QA)
		for f in frames:
			for y in range(0, int(info.cell_h), step):
				for x in range(0, int(info.cell_w), step):
					if image.get_pixel(f * int(info.cell_w) + x, y).a < 0.5:
						continue
					var point := (Vector2(x, y) - Vector2(info.pivot[0], info.pivot[1])) * scale
					seen[Vector2i(point.round())] = true
	var list: Array = seen.keys()
	list.sort_custom(func(a, b): return Vector2(a).length_squared() > Vector2(b).length_squared())
	var points := PackedVector2Array()
	for p in list:
		points.append(Vector2(p))
	_pose_points[key] = points
	return points


## Blood drops from a spurt landing on the floor: [[position, size], ...].
func add_stains(drops: Array) -> void:
	_queue({"kind": "stains", "drops": drops})


## The dying is over: paint its pool and body into the floor for good.
func finish_kill(dying: DyingBody) -> void:
	if dying.is_pixel():
		_queue({
			"kind": "pixel_body",
			"pool_frame": dying.pool_frame(),
			"pool_at": dying.pool_center(),
			"pool_turn": dying._pool_turn,
			"pool_size": dying.pool_size(),
			"pool_radius": dying.pool_radius(),
			"at": dying.at,
			"direction": dying.direction,
			"corpse": dying.corpse,
		})
		return
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
			if local.distance_to(child.pool_center()) < child.pool_radius() * 0.65:
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
					_pixel_dot(drop[0], drop[1], blood_color if randf() < 0.7 else dark_blood_color)
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
			"pixel_body":
				if stamp.pool_frame >= 0:
					HdBody.draw_frame(_painter, "blood_pool", stamp.pool_frame, stamp.pool_at, stamp.pool_turn, stamp.pool_size)
					_mark_wet(stamp.pool_at, stamp.pool_radius * 0.8)
				draw_body(_painter, stamp.at, stamp.direction, Color.WHITE, stamp.corpse, false)
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
		var length := _open_length(at, angle, randf_range(12.0, reach * 0.8))
		var end := at + Vector2.from_angle(angle) * length
		var width := randf_range(0.75, 1.5)
		for step in int(length / BLOOD_PIXEL):
			_pixel_dot(at.lerp(end, step * BLOOD_PIXEL / length), width, blood_color)
		_pixel_dot(end, randf_range(1.5, 2.5), blood_color)
		_mark_wet(end, 1.5)

	# The Art Director's splats: a couple of big pixel splashes in the spray.
	if not explosive:
		for i in 2:
			var turn := direction.angle() + randf_range(-spread, spread) * 0.5
			var splash := at + Vector2.from_angle(turn) * maxf(_open_length(at, turn, randf_range(10.0, reach * 0.6)) - 4.0, 0.0)
			HdBody.draw_frame(_painter, "blood_splat", randi_range(0, 3), splash, PI * 0.5 * randi_range(0, 3))
			_mark_wet(splash, 4.0)

	# Spray: lots of small drops, denser close to the body.
	for i in drops:
		var angle := direction.angle() + randf_range(-spread, spread)
		var distance := _open_length(at, angle, pow(randf(), 1.6) * reach + 3.0)
		var color := blood_color if randf() < 0.75 else dark_blood_color
		var size := randf_range(0.6, 2.4)
		_pixel_dot(at + Vector2.from_angle(angle) * distance, size, color)
		if size >= 1.8:
			_mark_wet(at + Vector2.from_angle(angle) * distance, size)


## How far blood thrown from `at` at `angle` gets, at most `length`: a wall
## or a door stops it, so it never lands in the next room.
func _open_length(at: Vector2, angle: float, length: float) -> float:
	if not is_inside_tree():
		return length
	var from := to_global(at)
	var ray := PhysicsRayQueryParameters2D.create(from, to_global(at + Vector2.from_angle(angle) * length), 1 | 16)
	var hit := get_world_2d().direct_space_state.intersect_ray(ray)
	return length if hit.is_empty() else maxf(from.distance_to(hit.position) - 0.5, 0.0)


## Blood is pixel art like the Art Director's pools and splats: drops and
## streaks are made of BLOOD_PIXEL squares, never smooth circles.
const BLOOD_PIXEL := 1.0 / 3.0


func _pixel_dot(center: Vector2, radius: float, color: Color) -> void:
	var lo := ((center - Vector2.ONE * radius) / BLOOD_PIXEL).floor()
	var hi := ((center + Vector2.ONE * radius) / BLOOD_PIXEL).ceil()
	var drew := false
	for y in range(int(lo.y), int(hi.y)):
		for x in range(int(lo.x), int(hi.x)):
			var cell := Vector2(x, y) * BLOOD_PIXEL
			if (cell + Vector2.ONE * BLOOD_PIXEL * 0.5).distance_to(center) <= radius:
				_painter.draw_rect(Rect2(cell, Vector2.ONE * BLOOD_PIXEL), color)
				drew = true
	if not drew:   # a tiny drop: one pixel
		_painter.draw_rect(Rect2((center / BLOOD_PIXEL).floor() * BLOOD_PIXEL, Vector2.ONE * BLOOD_PIXEL), color)


## One footprint: the Art Director's red print for that walker (a left
## shoe or a paw, toe down), in 4 stages from fresh (0) to faint (3) as the
## blood wears off; mirrored for the right foot, turned the way the walker
## went. `alpha` (BloodyFeet: how much blood is left) picks the stage, and
## the last of it fades out.
func _paint_footprint(stamp: Dictionary) -> void:
	var kind: String = stamp.kind_of_foot
	var info := HdBody.info_of("footprint_paw" if kind == "dog" else "footprint_shoe")
	var stage := clampi(int((1.0 - stamp.alpha) * 4.0), 0, 3)
	var cell := Vector2(info.cell_w, info.cell_h)
	var size := float(info.game_scale)   # 1/3: a shoe print is 24 px = 0.27 m
	var flip := 1.0 if stamp.left or kind == "dog" else -1.0
	_painter.draw_set_transform(stamp.at, stamp.angle - PI * 0.5, Vector2(size * flip, size))
	_painter.draw_texture_rect_region(HdBody._texture(info.file), Rect2(-Vector2(info.pivot[0], info.pivot[1]), cell),
			Rect2(Vector2(cell.x * stage, 0), cell), Color(1, 1, 1, clampf(stamp.alpha * 2.0, 0.0, 1.0)))
	_painter.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws a body lying on the floor onto `canvas` (the gore image, or a
## DyingBody while it twitches). `legs` bends the legs by that many radians.
static func draw_body(canvas: CanvasItem, at: Vector2, direction: Vector2, color: Color, corpse: Dictionary, gory: bool, legs: float = 0.0) -> void:
	if corpse.get("torn", false):
		_draw_torn(canvas, at, color)
	elif corpse.has("pixel"):
		HdBody.draw_frame(canvas, corpse.pixel + "_dead" + corpse.get("variant", ""), 0, at, direction.angle() + PI * 0.5, float(corpse.get("size", 1.0)))
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

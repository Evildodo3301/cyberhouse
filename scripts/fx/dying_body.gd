class_name DyingBody
extends Node2D
## The few seconds after a kill: the body lies there with its legs shivering,
## blood pumps out of the wound in spurts that get weaker with each
## heartbeat, and a pool spreads out underneath. When it's over, the body
## and the pool are painted into the gore layer for good (so they cost
## nothing to draw any more) and this node goes away.
##
## Blood setting: FULL = spurts, pulsing veins and a big pool; REDUCED = no
## spurts, a small pool; OFF = no blood at all, only the twitch.
##
## Made by GoreLayer.add_kill(); nothing else needs to create one. It sits
## at the gore layer's origin, so it draws in the same coordinates.

## How long the whole thing lasts, in seconds.
const DURATION := 4.0
## Seconds between spurts at first; the heart slows down as it goes.
const FIRST_BEAT := 0.42
const LAST_BEAT := 0.8
## Spurts stop after this long (the pool keeps spreading a little).
const SPURT_TIME := 3.0
## Pool radius it spreads to, in pixels, per blood setting.
const POOL_FULL := 13.0
const POOL_REDUCED := 6.0
## Legs stop twitching after this long.
const TWITCH_TIME := 2.6
## Pixel bodies (corpse {"pixel": who}): the Art Director's pool spreads
## over this long, then holds its last frame. REDUCED blood stops at frame 3.
const POOL_TIME := 2.3
const POOL_LAST := 9
const POOL_LAST_REDUCED := 3
## The pixel spurt: 6 frames (three beats, the third weaker), then a pause
## of 2, over and over while the heart still pumps.
const SPURT_STEPS := 8

var gore: GoreLayer
var at: Vector2               # where the body lies (gore layer coordinates)
var direction: Vector2        # head points this way
var body_color: Color
var corpse: Dictionary        # see GoreLayer.add_kill
var gory: bool                # use the burst-head corpse frame
var blood_level: int = 0      # Game.BloodLevel when it died

var _time: float = 0.0
var _next_beat: float = 0.12
var _beat_glow: float = 0.0   # 1 right after a spurt, fades: veins flash
var _drops: Array[Dictionary] = []   # blood in the air: pos, vel, life, size
var _landed: Array = []              # drops that hit the floor this frame
var _pool_shape := PackedFloat32Array()   # 12 lumpy radius multipliers
var _veins: Array[PackedVector2Array] = []
var _spurt_angle: float
var _twitch_seed: float
var _pool_turn: float         # pixel pools are turned a quarter turn or so, so no two look alike
static var _pool_radii: Array = []   # pixel pool: how far each frame reaches, at scale 1


func _ready() -> void:
	for i in 12:
		_pool_shape.append(randf_range(0.65, 1.0))
	if is_pixel():
		_spurt_angle = direction.angle() + randf_range(-0.6, 0.6)   # the Art Director's jet: away from the shooter
	else:
		_spurt_angle = direction.angle() + PI + randf_range(-0.9, 0.9)   # out of the wound, back the way the hit came
	_pool_turn = PI * 0.5 * randi_range(0, 3)
	_twitch_seed = randf_range(0.2, 1.2)   # the first fit starts straight away
	# A few short squiggles at the wound: the veins that pump.
	for i in 3:
		var vein := PackedVector2Array([Vector2.ZERO])
		var heading := _spurt_angle + randf_range(-1.2, 1.2)
		for step in 3:
			heading += randf_range(-0.6, 0.6)
			vein.append(vein[vein.size() - 1] + Vector2.from_angle(heading) * randf_range(1.5, 2.5))
		_veins.append(vein)


func _process(delta: float) -> void:
	_time += delta
	_beat_glow = maxf(_beat_glow - delta * 3.0, 0.0)
	if blood_level == Game.BloodLevel.FULL and _time >= _next_beat and _time < SPURT_TIME:
		_spurt()
		_next_beat += lerpf(FIRST_BEAT, LAST_BEAT, _time / SPURT_TIME)
	for drop in _drops:
		drop.pos += drop.vel * delta
		drop.vel *= 0.9
		drop.life -= delta
		if drop.life <= 0.0:
			_landed.append([drop.pos, drop.size])
	_drops = _drops.filter(func(d): return d.life > 0.0)
	if not _landed.is_empty():
		gore.add_stains(_landed)
		_landed = []
	if _time >= DURATION:
		gore.finish_kill(self)
		queue_free()
		return
	queue_redraw()


## One heartbeat: a jet of drops out of the wound, weaker every time.
func _spurt() -> void:
	var strength := exp(-_time / 1.4)
	_beat_glow = 1.0
	_spurt_angle += randf_range(-0.25, 0.25)   # the jet wanders a little
	for i in int(4 + 8 * strength):
		var speed := randf_range(50.0, 120.0) * (0.4 + strength)
		_drops.append({
			"pos": _wound(),
			"vel": Vector2.from_angle(_spurt_angle + randf_range(-0.2, 0.2)) * speed,
			"life": randf_range(0.12, 0.3),
			"size": randf_range(0.7, 1.5) * (0.6 + strength * 0.6),
		})


func _wound() -> Vector2:
	return at + direction * 2.0


## True for the Art Director's pixel bodies: they play their death
## animation and bleed the pixel pool and spurt.
func is_pixel() -> bool:
	return corpse.has("pixel")


## The pixel pool's frame right now (-1: no pool).
func pool_frame() -> int:
	var last: int = {Game.BloodLevel.FULL: POOL_LAST, Game.BloodLevel.REDUCED: POOL_LAST_REDUCED}.get(blood_level, -1)
	if last < 0:
		return -1
	return mini(int(_time / POOL_TIME * (POOL_LAST + 1)), last)


## How big the pixel pool is drawn: the dog bleeds a smaller one (0.8x).
func pool_size() -> float:
	return 0.8 if corpse.get("pixel", "") == "dog" else 1.0


## Where the pool is centred.
func pool_center() -> Vector2:
	return at if is_pixel() else at + direction * 4.0


## How far the pool has spread right now (fast at first, then slower).
func pool_radius() -> float:
	if is_pixel():
		var index := pool_frame()
		return 0.0 if index < 0 else _pool_radius_of(index) * pool_size()
	var full: float = {Game.BloodLevel.FULL: POOL_FULL, Game.BloodLevel.REDUCED: POOL_REDUCED}.get(blood_level, 0.0)
	return full * (1.0 - exp(-_time / 1.1))


## The pool's outline at a given radius (the same lumps every frame).
func pool_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var middle := at + direction * 4.0
	for i in 12:
		points.append(middle + Vector2.from_angle(TAU * i / 12.0) * maxf(radius * _pool_shape[i], 0.5))
	return points


## How far the pixel pool's frame `index` reaches from its middle, in room
## px at size 1 (half the smaller side of what's drawn in it).
static func _pool_radius_of(index: int) -> float:
	if _pool_radii.is_empty():
		var info := HdBody.info_of("blood_pool")
		var image: Image = HdBody._texture(info.file).get_image()
		if image.is_compressed():
			image.decompress()
		for i in int(info.frames):
			var used := image.get_region(Rect2i(i * int(info.cell_w), 0, int(info.cell_w), int(info.cell_h))).get_used_rect()
			_pool_radii.append(minf(used.size.x, used.size.y) * 0.5 * float(info.game_scale))
	return _pool_radii[index]


## How far the legs are bent this frame, in radians: shivers in short fits
## that die away.
func leg_twitch() -> float:
	if _time > TWITCH_TIME:
		return 0.0
	var fade := 1.0 - _time / TWITCH_TIME
	var fits := maxf(sin(_time * 7.0 + _twitch_seed), 0.0)   # on, off, on...
	return sin(_time * 60.0) * 0.14 * fade * fits


func _draw() -> void:
	if is_pixel():
		_draw_pixel()
		return
	var radius := pool_radius()
	if radius > 0.5:
		draw_colored_polygon(pool_polygon(radius), gore.dark_blood_color)
	GoreLayer.draw_body(self, at, direction, body_color, corpse, gory, leg_twitch())
	if blood_level == Game.BloodLevel.FULL and _time < SPURT_TIME:
		var vein_color := gore.dark_blood_color.lerp(gore.blood_color.lightened(0.3), _beat_glow)
		for vein in _veins:
			var placed := PackedVector2Array()
			for point in vein:
				placed.append(_wound() + point)
			draw_polyline(placed, vein_color, 1.0)
	for drop in _drops:
		draw_line(drop.pos, drop.pos - drop.vel * 0.025, gore.blood_color, drop.size)
		draw_circle(drop.pos, drop.size, gore.blood_color)


## The Art Director's pixel version: the pool spreads underneath, the body
## plays its death (the leg shiver is in the frames) and the wound spurts.
func _draw_pixel() -> void:
	var pool := pool_frame()
	if pool >= 0:
		HdBody.draw_frame(self, "blood_pool", pool, pool_center(), _pool_turn, pool_size())
	var who: String = corpse.pixel
	var death := HdBody.info_of(who + "_death")
	var index := mini(int(_time * float(death.get("fps", 12))), int(death.get("frames", 1)) - 1)
	HdBody.draw_frame(self, who + "_death", index, at, direction.angle() + PI * 0.5, float(corpse.get("size", 1.0)))
	if blood_level == Game.BloodLevel.FULL and _time < SPURT_TIME:
		var step := int(_time * float(HdBody.info_of("blood_spurt").get("fps", 12))) % SPURT_STEPS
		if step < 6:
			var fade := Color(1, 1, 1, clampf(1.6 - _time / SPURT_TIME, 0.0, 1.0))
			HdBody.draw_frame(self, "blood_spurt", step, _wound(), _spurt_angle + PI * 0.5, 1.0, fade)
		var vein_color := gore.dark_blood_color.lerp(gore.blood_color.lightened(0.3), _beat_glow)
		for vein in _veins:
			var placed := PackedVector2Array()
			for point in vein:
				placed.append(_wound() + point)
			draw_polyline(placed, vein_color, 1.0)
	for drop in _drops:
		draw_rect(Rect2((drop.pos - Vector2.ONE * drop.size * 0.5).floor(), Vector2.ONE * ceilf(drop.size)), gore.blood_color)

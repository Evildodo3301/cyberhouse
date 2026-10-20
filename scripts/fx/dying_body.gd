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


func _ready() -> void:
	for i in 12:
		_pool_shape.append(randf_range(0.65, 1.0))
	_spurt_angle = direction.angle() + PI + randf_range(-0.9, 0.9)   # out of the wound, back the way the hit came
	_twitch_seed = randf() * 10.0
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


## How far the pool has spread right now (fast at first, then slower).
func pool_radius() -> float:
	var full: float = {Game.BloodLevel.FULL: POOL_FULL, Game.BloodLevel.REDUCED: POOL_REDUCED}.get(blood_level, 0.0)
	return full * (1.0 - exp(-_time / 1.1))


## The pool's outline at a given radius (the same lumps every frame).
func pool_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var middle := at + direction * 4.0
	for i in 12:
		points.append(middle + Vector2.from_angle(TAU * i / 12.0) * maxf(radius * _pool_shape[i], 0.5))
	return points


## How far the legs are bent this frame, in radians: shivers in short fits
## that die away.
func leg_twitch() -> float:
	if _time > TWITCH_TIME:
		return 0.0
	var fade := 1.0 - _time / TWITCH_TIME
	var fits := maxf(sin(_time * 7.0 + _twitch_seed), 0.0)   # on, off, on...
	return sin(_time * 60.0) * 0.14 * fade * fits


func _draw() -> void:
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

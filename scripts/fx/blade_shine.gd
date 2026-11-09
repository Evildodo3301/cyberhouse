class_name BladeShine
extends RefCounted
## A star glint that runs along a blade (WeaponData.blade_shine): every
## couple of seconds at rest, and again and again while the blade moves
## (walking with it, swinging, flying after a throw).
##
## Each owner keeps one: call update() every frame, then draw() where the
## blade is (two points, in the canvas item's own coordinates).

const GLINT_TIME := 0.22     # seconds one glint takes to run along the blade
const IDLE_GAP := 2.0        # seconds between glints at rest
const MOVING_GAP := 0.12     # seconds between glints while it moves
const COLOR := Color(1.0, 0.98, 0.85)

var _t: float = -1.0         # 0..1 along the blade (-1 = no glint now)
var _wait: float = 0.0

## Blade lines found in each frame of a texture strip, cached: [a, b] in the
## frame's own pixels (centre = 0, 0), or [] if no blade.
static var _lines := {}


func _init() -> void:
	_wait = randf() * IDLE_GAP   # several blades in a room don't glint together


func update(delta: float, moving: bool) -> void:
	if _t >= 0.0:
		_t += delta / GLINT_TIME
		if _t >= 1.0:
			_t = -1.0
			_wait = MOVING_GAP if moving else IDLE_GAP
		return
	_wait -= delta
	if moving:
		_wait = minf(_wait, MOVING_GAP)
	if _wait <= 0.0:
		_t = 0.0


func active() -> bool:
	return _t >= 0.0


## Draws the glint on `canvas` at its spot between `a` and `b`.
func draw(canvas: CanvasItem, a: Vector2, b: Vector2, size: float = 3.0) -> void:
	if _t < 0.0:
		return
	var at := a.lerp(b, _t)
	var r := size * sin(_t * PI)   # grows, then fades
	var c := Color(COLOR, 0.95)
	canvas.draw_line(at - Vector2(r, 0), at + Vector2(r, 0), c, 1.0)
	canvas.draw_line(at - Vector2(0, r), at + Vector2(0, r), c, 1.0)
	var d := r * 0.45
	canvas.draw_line(at - Vector2(d, d), at + Vector2(d, d), Color(COLOR, 0.6), 0.6)
	canvas.draw_line(at - Vector2(d, -d), at + Vector2(d, -d), Color(COLOR, 0.6), 0.6)
	canvas.draw_circle(at, maxf(r * 0.3, 0.4), Color.WHITE)


## The blade in `frame` of a strip of `count` frames: the two ends of the
## biggest patch of light steel-grey pixels. Coordinates are relative to the
## frame's centre, in texture pixels.
static func blade_line(texture: Texture2D, count: int, frame: int) -> Array:
	var key := "%s#%d" % [texture.resource_path, frame]
	if _lines.has(key):
		return _lines[key]
	var image := texture.get_image()
	var line := []
	if image:
		if image.is_compressed():
			image.decompress()
		var rect := WeaponData.frame_rect(texture, count, frame)
		var steel := {}
		for y in int(rect.size.y):
			for x in int(rect.size.x):
				var c := image.get_pixel(int(rect.position.x) + x, y)
				if c.a > 0.5 and c.r > 0.62 and c.g > 0.62 and c.b > 0.65 and absf(c.r - c.b) < 0.18:
					steel[Vector2i(x, y)] = true
		# Biggest 8-connected patch (the blade, not the thin swing streak).
		var best: Array = []
		var seen := {}
		for start in steel:
			if seen.has(start):
				continue
			var patch: Array = []
			var stack: Array = [start]
			seen[start] = true
			while not stack.is_empty():
				var p: Vector2i = stack.pop_back()
				patch.append(p)
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						var q := p + Vector2i(dx, dy)
						if steel.has(q) and not seen.has(q):
							seen[q] = true
							stack.append(q)
			if patch.size() > best.size():
				best = patch
		if best.size() >= 3:
			# Its two ends: the pair of pixels furthest apart.
			var a: Vector2i = best[0]
			for p in best:
				if Vector2(p - best[0]).length_squared() > Vector2(a - best[0]).length_squared():
					a = p
			var b: Vector2i = a
			for p in best:
				if Vector2(p - a).length_squared() > Vector2(b - a).length_squared():
					b = p
			var centre := rect.size / 2.0
			line = [Vector2(a) + Vector2(0.5, 0.5) - centre, Vector2(b) + Vector2(0.5, 0.5) - centre]
	_lines[key] = line
	return line

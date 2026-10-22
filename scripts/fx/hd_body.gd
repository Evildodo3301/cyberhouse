class_name HdBody
extends Sprite2D
## A character drawn with the Art Director's HD frames (hero, suit enemy,
## doberman). One sprite shows the whole body; the owner picks the
## animation and frame and turns it to face the aim.
##
## The frames all face DOWN, each animation has its own sheet, cell size,
## scale and rotation centre (pivot): see assets/characters/hd/hd_anims.json.
## The sheets' pivot is the head for people, but these are high-angle
## frames: the body reaches about 30 px out in front of the head. Turning
## around the head would draw most of him ahead of where he really is (his
## hitbox), into furniture and walls. So people turn around the middle of
## the body instead: BODY_FORWARD px in front of the head. The dog already
## turns around its middle.

## The sheets' game_scale assumes one screen pixel per room pixel, but the
## camera zooms in 3x. This makes people the old size in the room (about
## 16 px across the shoulders, the dog about 22 px long): Fianso wants
## normal people in big rooms. 0.614 would be 1.5x (option D, tried and
## dropped). Change this one number to resize every HD character.
static var room_scale := 0.409
## How far in front of the head the middle of a person's body is, in room px
## at room_scale 0.614 (it shrinks and grows with the body: 8 px now).
const BODY_FORWARD := 12.0
const ANIMS_FILE := "res://assets/characters/hd/hd_anims.json"
const OUTLINE := preload("res://shaders/outline.gdshader")
const IMPLANT_CODE := preload("res://shaders/implant_code.gdshader")

static var _anims: Dictionary = {}
static var _textures: Dictionary = {}

## "hero", "enemy" or "dog": the start of every animation's name.
var who: String = "hero"
var current: String = ""


## `outline`: a coloured outline (the hero's teal). `code`: the enemy's
## green implant code running down the suit.
func setup(character: String, outline := Color.TRANSPARENT, code := false) -> void:
	who = character
	centered = true
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var material := ShaderMaterial.new()
	if code:
		material.shader = IMPLANT_CODE
	elif outline.a > 0.0:
		material.shader = OUTLINE
		material.set_shader_parameter("outline_color", outline)
		material.set_shader_parameter("width", 3.0)   # sheet pixels: a little under one room pixel
	if code:
		material.set_shader_parameter("glyphs", preload("res://assets/characters/hd/implant_glyphs.png"))
	if material.shader:
		self.material = material
	show_anim("idle", 0)


## True if this character has that animation ("walk", "punch", ...).
func has_anim(anim: String) -> bool:
	return _info(anim).size() > 0


func frame_count(anim: String) -> int:
	return int(_info(anim).get("frames", 1))


func fps(anim: String) -> float:
	return float(_info(anim).get("fps", 12))


## The frame to show `seconds` into a one-shot animation (holds the last
## frame at the end), following the sheet's play order if it has one.
func frame_at(anim: String, seconds: float) -> int:
	var info := _info(anim)
	var order: Array = info.get("play_order", range(int(info.get("frames", 1))))
	return order[clampi(int(seconds * float(info.get("fps", 12))), 0, order.size() - 1)]


## How long a one-shot animation takes.
func length(anim: String) -> float:
	var info := _info(anim)
	var steps: int = info.get("play_order", []).size() if info.has("play_order") else int(info.get("frames", 1))
	return steps / float(info.get("fps", 12))


func show_anim(anim: String, index: int) -> void:
	var info := _info(anim)
	if info.is_empty():
		return
	var name := who + "_" + anim
	if current != name:
		current = name
		texture = _texture(info.file)
		hframes = int(info.frames)
		scale = Vector2.ONE * float(info.game_scale) * room_scale
		var cell := Vector2(info.cell_w, info.cell_h)
		offset = cell / 2.0 - Vector2(info.pivot[0], info.pivot[1])
		if who != "dog":
			offset.y -= BODY_FORWARD * room_scale / 0.614 / scale.y   # the frames face down: forward is +y
		if material is ShaderMaterial and material.shader == IMPLANT_CODE:
			material.set_shader_parameter("game_scale", float(info.game_scale) * room_scale)
	frame = clampi(index, 0, hframes - 1)


## The blade in the frame showing now (a machete swipe), as two points in
## `space`'s coordinates; empty if this frame shows no blade.
func blade_points(space: Node2D) -> Array:
	var line := BladeShine.blade_line(texture, hframes, frame)
	if line.is_empty():
		return []
	var to_space := space.get_global_transform().affine_inverse() * get_global_transform()
	return [to_space * (line[0] + offset), to_space * (line[1] + offset)]


## The blade of a weapon drawn in hand from its floor picture, placed in
## `rect` and turned by `transform`, as two points (empty if none found).
static func held_blade_points(weapon: WeaponData, transform: Transform2D, rect: Rect2) -> Array:
	var line := BladeShine.blade_line(weapon.floor_texture, 1, 0)
	if line.is_empty():
		return []
	var size := weapon.floor_texture.get_size()
	return line.map(func(p: Vector2): return transform * (rect.position + (p + size / 2.0) * rect.size / size))


## Turn to face `direction` (the frames face down).
func face(direction: Vector2) -> void:
	rotation = direction.angle() - PI * 0.5


func _info(anim: String) -> Dictionary:
	if _anims.is_empty():
		_anims = load(ANIMS_FILE).data.anims   # imported as a JSON resource, so it ships in the APK
	return _anims.get(who + "_" + anim, {})


static func _texture(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load(ANIMS_FILE.get_base_dir().path_join(file))
	return _textures[file]

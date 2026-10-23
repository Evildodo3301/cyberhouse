class_name HdBody
extends Sprite2D
## A character drawn with the Art Director's pixel-art frames (set B: hero,
## suit enemy, doberman; strict top-down). One sprite shows the whole body;
## the owner picks the animation and frame and turns it to face the aim.
##
## The frames all face DOWN, each animation has its own sheet, cell size and
## rotation centre (pivot, the middle of the body): see
## assets/characters/pixel/pixel_anims.json. 1 sprite pixel = 0.5 room pixel
## (game_scale), drawn with no smoothing so it stays pixel art.

## Resize every character at once (1 = the Art Director's 0.5 rule). 2/3
## makes one sprite pixel exactly one screen pixel at the 3x camera, so the
## pixel art stays crisp, and people are the size the houses were built for
## (about 0.5 m across; Fianso: normal people in big rooms).
static var room_scale := 2.0 / 3.0
## Characters with a fixed size, whatever room_scale says: the doberman
## stays at the Art Director's 0.5 rule (1.1 m).
const FIXED_SIZE := {"dog": 1.0}
## Each character's body for collisions, fitted to the outline of its idle,
## walk and gun frames so the picture never pokes into a wall or furniture
## (Fianso): [half width, length, how far the middle sits in front of the
## pivot], room px at the Art Director's size (times size()). It's a capsule
## that turns with the picture (face()).
const BODY_SHAPES := {
	"hero": [11.0, 29.0, 3.5],
	"enemy": [12.0, 37.0, 1.5],
	"dog": [9.5, 34.0, 0.75],
}
const ANIMS_FILE := "res://assets/characters/pixel/pixel_anims.json"
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
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # pixel art: no smoothing
	var material := ShaderMaterial.new()
	if code:
		material.shader = IMPLANT_CODE
	elif outline.a > 0.0:
		material.shader = OUTLINE
		material.set_shader_parameter("outline_color", outline)
		material.set_shader_parameter("width", 1.0)   # one sheet pixel
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
		scale = Vector2.ONE * float(info.game_scale) * size()
		var cell := Vector2(info.cell_w, info.cell_h)
		offset = cell / 2.0 - Vector2(info.pivot[0], info.pivot[1])
		if material is ShaderMaterial and material.shader == IMPLANT_CODE:
			material.set_shader_parameter("game_scale", 1.0)   # glyphs in sprite pixels: as crisp as the pixel art
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
	var tex_size := weapon.floor_texture.get_size()
	return line.map(func(p: Vector2): return transform * (rect.position + (p + tex_size / 2.0) * rect.size / tex_size))


## Turn to face `direction` (the frames face down). The owner's collision
## body turns with the picture.
func face(direction: Vector2) -> void:
	rotation = direction.angle() - PI * 0.5
	var body := _body_shape()
	if body:
		body.rotation = rotation
		body.position = direction.normalized() * float(BODY_SHAPES[who][2]) * size() if direction != Vector2.ZERO else body.position


## Gives the owner (the player or an enemy) a collision body the shape of
## this character's picture (BODY_SHAPES).
func fit_collision() -> void:
	var body := _body_shape()
	if body == null or not BODY_SHAPES.has(who):
		return
	var capsule := CapsuleShape2D.new()
	capsule.radius = BODY_SHAPES[who][0] * size()
	capsule.height = BODY_SHAPES[who][1] * size()
	body.shape = capsule
	face(Vector2.DOWN)


## How much bigger than the Art Director's size this character is drawn.
func size() -> float:
	return FIXED_SIZE.get(who, room_scale)


func _body_shape() -> CollisionShape2D:
	return get_parent().get_node_or_null("CollisionShape2D") as CollisionShape2D if get_parent() else null


func _info(anim: String) -> Dictionary:
	if _anims.is_empty():
		_anims = load(ANIMS_FILE).data.anims   # imported as a JSON resource, so it ships in the APK
	return _anims.get(who + "_" + anim, {})


static func _texture(file: String) -> Texture2D:
	if not _textures.has(file):
		_textures[file] = load(ANIMS_FILE.get_base_dir().path_join(file))
	return _textures[file]

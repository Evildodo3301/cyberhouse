class_name LevelMap
extends Node2D
## Builds a whole level from a text map, so a level can be changed by
## editing letters instead of placing nodes by hand. One letter = one tile
## (tile_px square; 8 px gives thin walls, 16 px = one character width):
##
##   #  wall              .  floor
##   (space)  open sky: you can't go there, and the neon void shows through
##   D  swinging door     o  open doorway (no door)
##      (a straight run of D's or o's in a wall = one doorway; 8 or more
##      D's, an even number, make a double door)
##   P  player start      g  pistol on the floor
##   m  machete on the floor
##   C  cop grunt with a pistol: shoots you, drops the pistol
##   M  cop grunt with a machete (drops it)    F  cop grunt, fists only
##   G  cop grunt with a machine gun: fires bursts, drops it
##   u  machine gun on the floor
##   V  civilian grunt with a pistol (looks like a cop for now, so the
##      player is the only one in pink; shoots, drops the pistol)
##   K  doberman: patrols, bites, carries nothing
##   E  exit (opens once every enemy is dead)
##   W  window wall: floor-to-ceiling glass with the city behind it.
##      Blocks like a wall.
##   S  stairs (a block of S's is one end of a staircase, see below)
##   x  floor with furniture on it (picture levels: the piece itself blocks;
##      levels without a picture yet: a plain block stands in for it)
##   ~  pool water: you can't walk in it, but bullets fly over it
##
## Two floors in one level: draw both floors in the same map with open sky
## (spaces) between them, put a block of S's on each floor, and link the two
## blocks with a furniture line "stairs x1 y1 x2 y2" (any tile of each
## block). Walking onto one end takes you to the other. The floor at the top
## of the map is floor 1. Enemies stay on their own floor.
##
## Rooms are worked out automatically: floor areas separated by walls and
## doorways. How enemies notice you is set per level (EnemySettings).
##
## Furniture goes in a second list, one item per line: "sofa 17 1" puts a
## sofa with its top-left corner on tile (17, 1). "floor_brick 5 5" gives
## the room around tile (5, 5) a brick floor; "floor_marble",
## "floor_dark_marble", "floor_bath", "floor_checker" (black and white
## kitchen tiles) and "floor_herringbone" (dark wood parquet) give it a fancy
## floor; other rooms get wood. Solid pieces block you,
## enemies and bullets (enemies path round them); rugs are floor decoration.
## Tall pieces (plants, lamps, statues) only block at their base (FOOTPRINTS),
## so you can brush past their leaves or shade; everything standing on the floor is
## drawn in order of how far down the screen its base is ("Y-sorting"), so
## whoever is lower down is drawn in front.
##
## Wall decor goes in the same list with a fourth word, the wall it hangs on:
## "painting_gold 40 0 up" hangs a painting on the north wall, starting at
## wall tile (40, 0). up / down / left / right = north / south / west / east
## wall. Decor is drawn on top of the wall, so it is never under anyone, and
## it isn't solid. Art: res://assets/levels/decor/<name>.png, drawn as if on
## a north wall (its bottom edge faces the room); it is turned for the others.
##
## More lines for enemies and doors:
##   "patrol 55 38 55 19"   the enemy on tile (55, 38) walks to (55, 19) and
##                          back (list as many points as you like: a loop)
##   "face 12 21 west"      the enemy on tile (12, 21) starts facing west
##                          (north / south / east / west, or degrees)
##   "door_out 42 15 up"    the door on tile (42, 15) only swings that way
##   "exit_walk west"       the exit is a staircase: once you step on it you
##                          walk off that way on your own, then the screen
##                          fades to the next floor (main.gd's next_floor)
##
## Picture levels: set `picture` to a finished drawing of the whole floor
## (walls, floors, paintings) and `picture_pieces` to its furniture list (a
## JSON file: each piece's picture, where it stands, and the box that
## blocks). The text map then only says what blocks and where things start.
## Art: Pixel 16 Interiors (free version) by zedpxl, see CREDITS.md.

const MACHETE := preload("res://data/weapons/machete.tres")
const MACHINE_GUN := preload("res://data/weapons/machine_gun.tres")
const GRUNT_SCENE := preload("res://scenes/enemies/grunt.tscn")
const DOOR_SCENE := preload("res://scenes/props/swing_door.tscn")
const PICKUP_SCENE := preload("res://scenes/weapons/weapon_pickup.tscn")
const EXIT_SCRIPT := preload("res://scripts/levels/exit_zone.gd")
const INTERIORS := preload("res://assets/levels/interiors.png")

## Furniture in the interiors sheet: region in the sheet, and whether it is solid.
const FURNITURE := {
	"bed_green": [Rect2(16, 96, 23, 32), true],
	"bed_blue": [Rect2(16, 128, 23, 32), true],
	"table": [Rect2(49, 107, 30, 21), true],
	"stool": [Rect2(83, 103, 11, 9), true],
	"cabinet": [Rect2(99, 115, 12, 13), true],
	"books": [Rect2(66, 131, 10, 13), true],
	"plant": [Rect2(49, 140, 12, 20), true],
	"lamp": [Rect2(68, 148, 9, 12), true],
	"sofa": [Rect2(82, 131, 44, 26), true],
	"desk": [Rect2(129, 147, 14, 13), true],
	"chair": [Rect2(145, 142, 14, 18), true],
	"chair_side": [Rect2(161, 141, 13, 19), true],
	"rug_oval": [Rect2(162, 65, 27, 14), false],
	"rug_blue": [Rect2(162, 81, 27, 14), false],
	"rug_orange": [Rect2(128, 80, 32, 16), false],
	"rug_green": [Rect2(133, 101, 36, 22), false],
}
## Gang carpets (A Velvet Fang, B Wire Crown, C Static Saints): a big rug in
## the middle of each big room and a mat at each door, each one a design
## picked at random. Teal so the blood shows up on them.
const GANG_RUGS := [
	preload("res://assets/levels/rugs/rug-A-velvet-fang-72x48.png"),
	preload("res://assets/levels/rugs/rug-B-wire-crown-72x48.png"),
	preload("res://assets/levels/rugs/rug-C-static-saints-72x48.png"),
]
const GANG_DOORMATS := [
	preload("res://assets/levels/rugs/doormat-A-velvet-fang-28x16.png"),
	preload("res://assets/levels/rugs/doormat-B-wire-crown-28x16.png"),
	preload("res://assets/levels/rugs/doormat-C-static-saints-28x16.png"),
]
## The fancy house furniture (our own, one file each in
## res://assets/levels/furniture/): whether it is solid. These names win
## over the interiors sheet's when both have one (plant, chair, desk).
const FANCY_FURNITURE := {
	"leopard_rug": false, "leopard_cushion": false,
	"white_sofa_long": true, "white_sofa_side": true, "glass_table": true,
	"tv_wall": true, "vinyl_cabinet": true, "piano": true, "desk": true,
	"chair": true, "bar_counter": true, "bar_stool": true, "gold_lamp": true,
	"plant": true, "statue": true, "kitchen_counter": true, "kitchen_sink": true,
	"stove": true, "fridge": true, "bathtub": true, "toilet": true,
	"bed": true, "nightstand": true,
}
## Pieces wider at the top than at the floor only block at their base: the
## blocking rectangle in the piece's own pixels (x, y, width, height). Anything not listed blocks with
## its whole picture.
const FOOTPRINTS := {
	"plant": Rect2(3, 3, 6, 6),       # the pot, under the leaves
	"statue": Rect2(2, 2, 7, 7),      # the plinth
	"gold_lamp": Rect2(2, 2, 5, 5),   # the stand, under the shade
}
## Wall decor (res://assets/levels/decor/<name>.png). Never solid.
const WALL_DECOR := ["painting_gold", "painting_portrait", "sconce", "wall_clock", "wood_panel"]
const DECOR_TURN := {"up": 0.0, "down": PI, "left": -PI / 2.0, "right": PI / 2.0}
const STAIRS_SCRIPT := preload("res://scripts/levels/stairs.gd")
## Physics layer for water: people can't walk in it, bullets fly over.
const WATER_LAYER := 32
## Floor tiles in the interiors sheet. Rooms take turns: wood, brick, wood...
const WOOD_TILES := [Rect2(96, 48, 16, 16), Rect2(112, 48, 16, 16)]
const BRICK_TILES := [Rect2(48, 32, 16, 16), Rect2(48, 48, 16, 16)]
## Fancy house floors (our own tiles): white marble for lounges and halls,
## black marble with gold veins for the kitchen, small white tiles for baths.
const FLOORS_V2 := preload("res://assets/levels/floors_v2.png")
const FANCY_FLOORS := {
	"marble": [Rect2(0, 0, 16, 16), Rect2(16, 0, 16, 16)],
	"dark_marble": [Rect2(32, 0, 16, 16), Rect2(48, 0, 16, 16)],
	"bath": [Rect2(64, 0, 16, 16), Rect2(80, 0, 16, 16)],
	"checker": [Rect2(0, 0, 16, 16), Rect2(16, 0, 16, 16)],
	"herringbone": [Rect2(32, 0, 16, 16), Rect2(48, 0, 16, 16)],
}
## Penthouse floors live in their own sheet; the rest are in FLOORS_V2.
const FLOORS_PENTHOUSE := preload("res://assets/levels/floors_penthouse.png")
const PENTHOUSE_FLOORS := ["checker", "herringbone"]
const GLASS := Color(0.32, 0.55, 0.7)
const GOLD := Color(0.78, 0.6, 0.25)
enum WallStyle { NEON, PLASTER }

@export_multiline var layout: String = ""
## Size of one letter in pixels. Doors are as long as their run of D's.
@export var tile_px: int = 16
## Furniture, one "name x y" per line (names: see FURNITURE).
@export_multiline var furniture: String = ""
## Darkens the floor tiles so the neon walls, blood and characters stand out.
@export var floor_tint: Color = Color(0.62, 0.55, 0.62)
@export var wall_color: Color = Color(0.55, 0.2, 1.0)    # neon purple
## NEON: glowing outlines. PLASTER: the fancy house look, plaster walls with
## a light cap line and red-brick pillars at corners and door frames.
@export var wall_style: WallStyle = WallStyle.NEON
@export var plaster_color: Color = Color(0.13, 0.24, 0.21)   # deep green
@export var cap_color: Color = Color(0.86, 0.82, 0.7)        # cream
@export var brick_color: Color = Color(0.6, 0.25, 0.17)
## Tint for the fancy floors (lighter than floor_tint: marble is meant to shine).
@export var fancy_floor_tint: Color = Color(0.8, 0.78, 0.8)
## Share of enemies (0 to 1) that will chase you out of their room. The rest
## stop at their own doorway. Early levels keep this low. Which enemies roam
## is fixed by map order, so it is the same on every retry.
@export_range(0.0, 1.0) var roam_chance: float = 0.15
## Rooms with at least this many floor tiles get a big gang rug in the middle.
@export var rug_min_tiles: int = 250
## Picks the rug designs and which side of each door its mat lies on. 0 = use
## the level's file name, so the carpets stay put on every retry.
@export var rug_seed: int = 0

@export_group("Picture level")
## A finished drawing of the whole floor, 1 px = 1 game px, top-left at 0, 0.
@export var picture: Texture2D
## Its furniture: JSON with "pieces": [{name, x, y, sort_y, collision: [x, y, w, h]}].
## Each piece's image is pieces/<name>.png next to the JSON file.
@export_file("*.json") var picture_pieces: String = ""
## Door colour on picture levels (dark wood instead of neon).
@export var door_color: Color = Color(0.95, 0.55, 0.15)

@export_group("Enemies")
## Tuning for the enemies this map spawns (empty = each keeps its own).
@export var enemy_settings: EnemySettings
## Tuning for the dobermans ("K").
@export var dog_settings: EnemySettings
## Share of human enemies (0 to 1) that walk a patrol round their room instead
## of standing guard. Dogs always patrol. Which ones is fixed per level.
@export_range(0.0, 1.0) var patrol_share: float = 0.0

## Size of the level in pixels.
var size_px: Vector2
var _rows: PackedStringArray
var _room_of_tile: Dictionary = {}   # Vector2i -> room index
var _walls: Array[Rect2] = []
var _floor_tiles: Array[Vector2i] = []
var _brick_rooms: Dictionary = {}   # room index -> true
var _solid_rects: Array[Rect2] = []   # solid furniture, for patrol routes
var _room_floor: Dictionary = {}    # room index -> a FANCY_FLOORS name
var _window_tiles: Array[Vector2i] = []   # W tiles: walls drawn as glass
var _floor_of_tile: Dictionary = {}   # Vector2i -> storey (1 = top of the map)
var _stair_lines: Array[PackedInt32Array] = []   # x1 y1 x2 y2 per "stairs" line
var _patrols: Dictionary = {}    # Vector2i -> Array[Vector2] from "patrol" lines
var _facings: Dictionary = {}    # Vector2i -> degrees from "face" lines
var _one_way_doors: Dictionary = {}   # Vector2i -> Vector2 from "door_out" lines
var _exit_walk := Vector2.ZERO           # from the "exit_walk" line
var _doors_by_tile: Dictionary = {}   # Vector2i -> the door node(s) of that doorway

## You took the stairs to another floor (main shows "FLOOR 2").
signal floor_changed(storey: int)


func _ready() -> void:
	add_to_group("level")   # enemies ask it which room a point is in
	_rows = layout.strip_edges().split("\n")
	# Windows behave exactly like walls; only their look differs.
	for y in _rows.size():
		for x in _rows[y].length():
			if _rows[y][x] == "W":
				_window_tiles.append(Vector2i(x, y))
		_rows[y] = _rows[y].replace("W", "#")
	# Furniture, enemies and the player (our sibling) are drawn lowest-base-last.
	y_sort_enabled = true
	if get_parent() is Node2D:
		get_parent().y_sort_enabled = true
	var width := 0
	for row in _rows:
		width = maxi(width, row.length())
	size_px = Vector2(width, _rows.size()) * tile_px
	_find_rooms()
	_build_walls()
	_build_doorways()
	if picture == null:
		_place_gang_rugs()
	_place_furniture()
	_place_picture_pieces()
	for at in _one_way_doors:
		for door in _doors_by_tile.get(at, []):
			door.open_only_toward(_one_way_doors[at])
	_build_stairs()
	_spawn_things()
	_build_navigation()
	var floor_drawer := Node2D.new()
	floor_drawer.z_index = -2   # under the rugs and the blood
	floor_drawer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	floor_drawer.draw.connect(_draw_floor.bind(floor_drawer))
	add_child(floor_drawer)
	var wall_drawer := Node2D.new()
	wall_drawer.z_index = 1     # walls cover any blood that splashes onto them
	wall_drawer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wall_drawer.draw.connect(_draw_walls.bind(wall_drawer))
	add_child(wall_drawer)


## The letter at a tile, or "#" outside the map.
func tile(at: Vector2i) -> String:
	if at.y < 0 or at.y >= _rows.size() or at.x < 0 or at.x >= _rows[at.y].length():
		return "#"
	return _rows[at.y][at.x]


func _tile_center(at: Vector2i) -> Vector2:
	return (Vector2(at) + Vector2(0.5, 0.5)) * tile_px


## Which room `point` is in, or -1 for walls and doorways.
func room_at(point: Vector2) -> int:
	return _room_of_tile.get(Vector2i((point / tile_px).floor()), -1)


## True if stepping onto `point` would take you out of room `room`: into a
## doorway or another room. Walls count as inside (bumping one is fine).
func leaves_room(room: int, point: Vector2) -> bool:
	var at := Vector2i((point / tile_px).floor())
	if tile(at) in ["D", "o"]:
		return true
	var there: int = _room_of_tile.get(at, -1)
	return there >= 0 and there != room


## True if any doorway tile (D or o) is within `radius` px of `point`.
func near_doorway(point: Vector2, radius: float) -> bool:
	var reach := int(ceil(radius / tile_px))
	var center := Vector2i((point / tile_px).floor())
	for y in range(center.y - reach, center.y + reach + 1):
		for x in range(center.x - reach, center.x + reach + 1):
			if not tile(Vector2i(x, y)) in ["D", "o"]:
				continue
			var closest := point.clamp(Vector2(x, y) * tile_px, Vector2(x + 1, y + 1) * tile_px)
			if closest.distance_to(point) <= radius:
				return true
	return false


func room_count() -> int:
	var rooms := {}
	for room in _room_of_tile.values():
		rooms[room] = true
	return rooms.size()


# ------------------------------------------------------------------ build

func _is_open(letter: String) -> bool:
	return not letter in ["#", "D", "o", " ", "~"]


## Flood-fills every floor area that walls and doorways separate.
func _find_rooms() -> void:
	var next_room := 0
	for y in _rows.size():
		for x in _rows[y].length():
			var start := Vector2i(x, y)
			if _is_open(tile(start)):
				_floor_tiles.append(start)
			if not _is_open(tile(start)) or _room_of_tile.has(start):
				continue
			var stack: Array[Vector2i] = [start]
			_room_of_tile[start] = next_room
			while not stack.is_empty():
				var here: Vector2i = stack.pop_back()
				for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					var there: Vector2i = here + step
					if _is_open(tile(there)) and not _room_of_tile.has(there):
						_room_of_tile[there] = next_room
						stack.append(there)
			next_room += 1
	# Doorway tiles are walkable floor too, they just belong to no room.
	for y in _rows.size():
		for x in _rows[y].length():
			if tile(Vector2i(x, y)) in ["D", "o"]:
				_floor_tiles.append(Vector2i(x, y))


## One body per horizontal run of "#" (drawn) or " " (open sky, not drawn),
## to keep the physics cheap.
func _build_walls() -> void:
	for y in _rows.size():
		var x := 0
		while x < _rows[y].length():
			var letter := tile(Vector2i(x, y))
			if not letter in ["#", " ", "~"] and not (letter == "x" and picture == null):
				x += 1
				continue
			var start := x
			while x < _rows[y].length() and tile(Vector2i(x, y)) == letter:
				x += 1
			var rect := Rect2(start * tile_px, y * tile_px, (x - start) * tile_px, tile_px)
			if letter == "#":
				_walls.append(rect)
			var body := StaticBody2D.new()
			# Layer 1 = "world" (stops bullets too); 32 = water (stops feet only).
			body.collision_layer = WATER_LAYER if letter == "~" else 1
			body.collision_mask = 0
			body.add_to_group("nav_walls")   # enemies' pathfinding avoids these
			body.position = rect.get_center()
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = rect.size
			shape.shape = rectangle
			body.add_child(shape)
			add_child(body)


	# The edge of the map: an invisible wall all round, for maps whose
	# outdoor floor runs right up to the edge.
	for edge in [Rect2(-tile_px, -tile_px, size_px.x + tile_px * 2, tile_px), Rect2(-tile_px, size_px.y, size_px.x + tile_px * 2, tile_px),
			Rect2(-tile_px, 0, tile_px, size_px.y), Rect2(size_px.x, 0, tile_px, size_px.y)]:
		var border := StaticBody2D.new()
		border.collision_layer = 1
		border.collision_mask = 0
		border.position = edge.get_center()
		var border_shape := CollisionShape2D.new()
		var border_rect := RectangleShape2D.new()
		border_rect.size = edge.size
		border_shape.shape = border_rect
		border.add_child(border_shape)
		add_child(border)


## Gang rugs and doormats, flat on the floor under the blood and furniture.
func _place_gang_rugs() -> void:
	var rng := RandomNumberGenerator.new()
	var level := get_parent()
	rng.seed = rug_seed if rug_seed != 0 else hash((level.scene_file_path if level else "") + str(name))
	# Big rooms: the rug spot nearest the room's middle that lies fully on its floor.
	var tiles_of_room := {}
	for at in _room_of_tile:
		tiles_of_room.get_or_add(_room_of_tile[at], []).append(at)
	var rug_tiles := Vector2i(GANG_RUGS[0].get_size() / tile_px)
	var rooms := tiles_of_room.keys()
	rooms.sort()
	for room in rooms:
		var tiles: Array = tiles_of_room[room]
		if tiles.size() < rug_min_tiles or _rooms_with_own_rug().has(room):
			continue
		var middle := Vector2.ZERO
		for at in tiles:
			middle += Vector2(at)
		middle /= tiles.size()
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for at in tiles:
			var corner: Vector2i = at
			var distance := (Vector2(corner) + Vector2(rug_tiles) * 0.5).distance_squared_to(middle + Vector2(0.5, 0.5))
			if distance < best_distance and _room_covers(room, corner, rug_tiles):
				best = corner
				best_distance = distance
		if best.x >= 0:
			_add_rug(GANG_RUGS[rng.randi() % GANG_RUGS.size()], Vector2(best * tile_px) + Vector2(rug_tiles * tile_px) * 0.5, 0.0)
	# A mat on one side of every door, picked at random, long side along the door.
	for door in get_children():
		if not door is SwingDoor:
			continue
		var along := Vector2.RIGHT.rotated(door.rotation)
		var side := along.orthogonal() * (1.0 if rng.randf() < 0.5 else -1.0)
		var spot: Vector2 = door.position + along * door.length * 0.5 + side * tile_px * 1.5
		_add_rug(GANG_DOORMATS[rng.randi() % GANG_DOORMATS.size()], spot, door.rotation)


## Rooms whose furniture list already has a big rug (they get no gang rug).
func _rooms_with_own_rug() -> Dictionary:
	var rooms := {}
	for line in furniture.strip_edges().split("\n", false):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 3 and parts[0] == "leopard_rug":
			rooms[_room_of_tile.get(Vector2i(int(parts[1]), int(parts[2])), -1)] = true
	return rooms


## True if every tile of the size x size block at `corner` is floor of `room`.
func _room_covers(room: int, corner: Vector2i, size: Vector2i) -> bool:
	for y in size.y:
		for x in size.x:
			if _room_of_tile.get(corner + Vector2i(x, y), -1) != room:
				return false
	return true


func _add_rug(texture: Texture2D, at: Vector2, turn: float) -> void:
	var rug := Sprite2D.new()
	rug.texture = texture
	rug.position = at
	rug.rotation = turn
	rug.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rug.z_index = -1   # on the floor, under the blood
	rug.add_to_group("rugs")
	add_child(rug)


## Puts each furniture line's sprite down; solid pieces get a body that
## blocks movement and bullets, and the enemies' pathfinding goes round it.
func _place_furniture() -> void:
	for line in furniture.strip_edges().split("\n", false):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 3 and parts[0] == "floor_brick":
			_brick_rooms[_room_of_tile.get(Vector2i(int(parts[1]), int(parts[2])), -1)] = true
			continue
		if parts.size() == 3 and parts[0].begins_with("floor_") and FANCY_FLOORS.has(parts[0].trim_prefix("floor_")):
			_room_floor[_room_of_tile.get(Vector2i(int(parts[1]), int(parts[2])), -1)] = parts[0].trim_prefix("floor_")
			continue
		if parts.size() >= 5 and parts.size() % 2 == 1 and parts[0] == "patrol":
			var points: Array[Vector2] = []
			for i in range(1, parts.size(), 2):
				points.append(_tile_center(Vector2i(int(parts[i]), int(parts[i + 1]))))
			_patrols[Vector2i(int(parts[1]), int(parts[2]))] = points
			continue
		if parts.size() == 4 and parts[0] == "face":
			var compass := {"east": 0.0, "south": 90.0, "west": 180.0, "north": -90.0}
			_facings[Vector2i(int(parts[1]), int(parts[2]))] = compass.get(parts[3], float(parts[3]))
			continue
		if parts.size() == 4 and parts[0] == "door_out" and DECOR_TURN.has(parts[3]):
			var away := {"up": Vector2.UP, "down": Vector2.DOWN, "left": Vector2.LEFT, "right": Vector2.RIGHT}
			_one_way_doors[Vector2i(int(parts[1]), int(parts[2]))] = away[parts[3]]
			continue
		if parts.size() == 2 and parts[0] == "exit_walk":
			var compass := {"east": Vector2.RIGHT, "south": Vector2.DOWN, "west": Vector2.LEFT, "north": Vector2.UP}
			_exit_walk = compass.get(parts[1], Vector2.ZERO)
			continue
		if parts.size() == 5 and parts[0] == "stairs":
			_stair_lines.append(PackedInt32Array([int(parts[1]), int(parts[2]), int(parts[3]), int(parts[4])]))
			continue
		if parts.size() == 4 and parts[0] in WALL_DECOR and DECOR_TURN.has(parts[3]):
			_hang_decor(parts[0], Vector2i(int(parts[1]), int(parts[2])), parts[3])
			continue
		if parts.size() != 3 or not (FURNITURE.has(parts[0]) or FANCY_FURNITURE.has(parts[0])):
			push_warning("LevelMap: bad furniture line '%s'" % line)
			continue
		var piece := Sprite2D.new()
		piece.name = parts[0].capitalize().replace(" ", "")
		var region: Rect2
		var solid: bool
		if FANCY_FURNITURE.has(parts[0]):
			piece.texture = load("res://assets/levels/furniture/%s.png" % parts[0])
			region = Rect2(Vector2.ZERO, piece.texture.get_size())
			solid = FANCY_FURNITURE[parts[0]]
			piece.add_to_group("fancy_furniture")
		else:
			region = FURNITURE[parts[0]][0]
			solid = FURNITURE[parts[0]][1]
			piece.texture = INTERIORS
			piece.region_enabled = true
			piece.region_rect = region
		piece.centered = false
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var corner := Vector2(int(parts[1]), int(parts[2])) * tile_px
		# The node sits at the piece's base, so Y-sorting goes by where it
		# stands; the picture is shifted back up to its corner.
		piece.position = corner + Vector2(0, region.size.y)
		piece.offset = Vector2(0, -region.size.y)
		if parts[0].ends_with("rug") or parts[0].begins_with("rug_"):
			piece.z_index = -1   # rugs: on the floor, under the blood
		add_child(piece)
		if solid:
			var foot: Rect2 = FOOTPRINTS.get(parts[0], Rect2(Vector2(1, 1), region.size - Vector2(2, 2)))
			foot.position += corner
			_solid_rects.append(foot)
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.add_to_group("nav_walls")
			body.position = foot.get_center()
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = foot.size
			shape.shape = rectangle
			body.add_child(shape)
			add_child(body)


## Picture levels: each furniture piece cut out of the drawing stands on the
## floor (Y-sorted by its base, sort_y) and blocks with its collision box.
func _place_picture_pieces() -> void:
	if picture == null or picture_pieces == "":
		return
	var folder := picture_pieces.get_base_dir()
	var data = load(picture_pieces).data
	for entry in data.pieces:
		var piece := Sprite2D.new()
		piece.name = String(entry.name).to_pascal_case()
		piece.texture = load("%s/pieces/%s.png" % [folder, entry.name])
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.centered = false
		piece.position = Vector2(entry.x, entry.sort_y)
		piece.offset = Vector2(0, entry.y - entry.sort_y)
		piece.add_to_group("picture_pieces")
		add_child(piece)
		var box := Rect2(entry.collision[0], entry.collision[1], entry.collision[2], entry.collision[3])
		_solid_rects.append(box)
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		body.add_to_group("nav_walls")
		body.position = box.get_center()
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = box.size
		shape.shape = rectangle
		body.add_child(shape)
		add_child(body)


## A painting, sconce or similar on a wall: turned to face the room, drawn
## over the wall (z 2) so nothing walks under it.
func _hang_decor(decor_name: String, at: Vector2i, side: String) -> void:
	var piece := Sprite2D.new()
	piece.name = decor_name.capitalize().replace(" ", "")
	piece.texture = load("res://assets/levels/decor/%s.png" % decor_name)
	piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	piece.rotation = DECOR_TURN[side]
	var size := piece.texture.get_size()
	if side in ["left", "right"]:
		size = Vector2(size.y, size.x)
	piece.position = Vector2(at) * tile_px + size * 0.5
	piece.z_index = 2
	piece.add_to_group("wall_decor")
	if tile(at) != "#":
		push_warning("LevelMap: %s at %s is not on a wall" % [decor_name, at])
	add_child(piece)


## Works out which floor (storey) every walkable tile is on, then joins
## each pair of S blocks named by a "stairs" line.
func _build_stairs() -> void:
	var walkable := func(at: Vector2i) -> bool: return _is_open(tile(at)) or tile(at) in ["D", "o"]
	var storeys: Array[Vector2i] = []   # first tile of each storey, top of the map first
	for at in _floor_tiles:
		if _floor_of_tile.has(at):
			continue
		storeys.append(at)
		var stack: Array[Vector2i] = [at]
		_floor_of_tile[at] = storeys.size()
		while not stack.is_empty():
			var here: Vector2i = stack.pop_back()
			for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var there: Vector2i = here + step
				if walkable.call(there) and not _floor_of_tile.has(there):
					_floor_of_tile[there] = storeys.size()
					stack.append(there)
	var count := 0
	for line in _stair_lines:
		var a := _stair_block(Vector2i(line[0], line[1]))
		var b := _stair_block(Vector2i(line[2], line[3]))
		if a.size == Vector2.ZERO or b.size == Vector2.ZERO:
			push_warning("LevelMap: a stairs line doesn't point at two blocks of S")
			continue
		count += 1
		var stairs: Node2D = STAIRS_SCRIPT.new()
		stairs.name = "Stairs%d" % count
		stairs.ends.assign([a, b])
		stairs.floors.assign([storey_at(a.get_center()), storey_at(b.get_center())])
		stairs.taken.connect(func(storey: int): floor_changed.emit(storey))
		add_child(stairs)


## The block of S tiles containing `at`, as a rectangle in map pixels.
func _stair_block(at: Vector2i) -> Rect2:
	if tile(at) != "S":
		return Rect2()
	var block := Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px)
	var stack: Array[Vector2i] = [at]
	var seen := {at: true}
	while not stack.is_empty():
		var here: Vector2i = stack.pop_back()
		block = block.merge(Rect2(Vector2(here) * tile_px, Vector2.ONE * tile_px))
		for step in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if tile(here + step) == "S" and not seen.has(here + step):
				seen[here + step] = true
				stack.append(here + step)
	return block


## Which floor a point is on (1 = the top of the map), or 0 off the floor.
func storey_at(point: Vector2) -> int:
	return _floor_of_tile.get(Vector2i((point / tile_px).floor()), 0)


## How many floors the level has.
func storey_count() -> int:
	var most := 0
	for storey in _floor_of_tile.values():
		most = maxi(most, storey)
	return most


## A straight run of D's becomes one swinging door hinged at its first tile.
func _build_doorways() -> void:
	var seen := {}
	var count := 0
	for y in _rows.size():
		for x in _rows[y].length():
			var at := Vector2i(x, y)
			if tile(at) != "D" or seen.has(at):
				continue
			var step := Vector2i.RIGHT if tile(at + Vector2i.RIGHT) == "D" else Vector2i.DOWN
			var length := 0
			while tile(at + step * length) == "D":
				seen[at + step * length] = true
				length += 1
			# 6 or more D's in a row (an even number) make a double door: two
			# halves hinged at the two ends, meeting in the middle.
			var halves := 2 if length >= 6 and length % 2 == 0 else 1
			var start := Vector2(at) * tile_px + Vector2(step.y, step.x) * tile_px * 0.5
			var leaves: Array[Node2D] = []
			for i in length:
				_doors_by_tile[at + step * i] = leaves
			for half in halves:
				count += 1
				var door: Node2D = DOOR_SCENE.instantiate()
				door.name = "Door%d" % count
				door.door_id = door.name
				door.length = length * tile_px / halves
				door.position = start + Vector2(step) * (length * tile_px * half)
				door.rotation = (0.0 if step == Vector2i.RIGHT else PI * 0.5) + PI * half
				if picture:
					door.color = door_color
				add_child(door)
				leaves.append(door)


func _spawn_things() -> void:
	var count := {"C": 0, "V": 0, "M": 0, "F": 0, "G": 0, "K": 0, "g": 0, "m": 0, "u": 0}
	var rng := RandomNumberGenerator.new()
	var level := get_parent()
	rng.seed = hash((level.scene_file_path if level else "") + "patrols")
	for at in _floor_tiles:
		var letter := tile(at)
		var spot := _tile_center(at)
		match letter:
			"P":
				var player := get_tree().get_first_node_in_group("player")
				if player == null:
					player = get_parent().get_node_or_null("Player")
				if player:
					player.global_position = spot
			"C", "V", "M", "F", "G", "K":
				count[letter] += 1
				var grunt: Node2D = GRUNT_SCENE.instantiate()
				grunt.name = {"C": "Cop%d", "V": "Civilian%d", "M": "Thug%d", "F": "Brawler%d", "G": "Gunner%d", "K": "Dog%d"}[letter] % count[letter]
				grunt.position = spot
				if enemy_settings:
					grunt.settings = enemy_settings
				if letter == "K":
					grunt.is_dog = true
					grunt.sheet = null   # placeholder dog until its art arrives
					grunt.body_color = Color(0.13, 0.09, 0.08)
					grunt.carried_weapon = null
					if dog_settings:
						grunt.settings = dog_settings
				if letter == "M":
					grunt.carried_weapon = MACHETE
				elif letter == "G":
					grunt.carried_weapon = MACHINE_GUN
				elif letter == "F":
					grunt.carried_weapon = null   # fists only, drops nothing
				# Every 1/roam_chance-th enemy (in map order) is a roamer.
				var index: int = count["C"] + count["V"] + count["M"] + count["F"] + count["G"] + count["K"]
				grunt.stays_in_room = floori(index * roam_chance) == floori((index - 1) * roam_chance)
				grunt.start_facing_degrees = _facings.get(at, rad_to_deg(spot.angle_to_point(_room_center(at))))
				if _patrols.has(at):
					grunt.patrol_points = _patrols[at]
					grunt.start_facing_degrees = _facings.get(at, rad_to_deg(spot.angle_to_point(_patrols[at][1])))
				elif letter == "K" or rng.randf() < patrol_share:
					grunt.patrol_points = _patrol_route(at, rng)
				add_child(grunt)
			"g":
				count["g"] += 1
				var pickup: Node2D = PICKUP_SCENE.instantiate()
				pickup.name = "Pistol%d" % count["g"]
				pickup.position = spot
				add_child(pickup)
			"m":
				count["m"] += 1
				var pickup: Node2D = PICKUP_SCENE.instantiate()
				pickup.name = "Machete%d" % count["m"]
				pickup.weapon = MACHETE
				pickup.position = spot
				add_child(pickup)
			"u":
				count["u"] += 1
				var pickup: Node2D = PICKUP_SCENE.instantiate()
				pickup.name = "MachineGun%d" % count["u"]
				pickup.weapon = MACHINE_GUN
				pickup.position = spot
				add_child(pickup)
			"E":
				pass
	# The exit: one zone covering every E tile.
	var exit_rect := Rect2()
	for at in _floor_tiles:
		if tile(at) == "E":
			var tile_rect := Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px)
			exit_rect = tile_rect if exit_rect.size == Vector2.ZERO else exit_rect.merge(tile_rect)
	if exit_rect.size != Vector2.ZERO:
		var exit_zone := Node2D.new()
		exit_zone.set_script(EXIT_SCRIPT)
		exit_zone.name = "Exit"
		exit_zone.rect = exit_rect
		exit_zone.walk = _exit_walk
		add_child(exit_zone)


## The middle of the room a tile belongs to (guards face into their room).
## A patrol round the room from `start`: the start, then two or three spots in
## the same room, each well clear of walls and solid furniture and at least
## 5 tiles from the last, so its back is turned to part of the room as it walks.
func _patrol_route(start: Vector2i, rng: RandomNumberGenerator) -> Array[Vector2]:
	var room: int = _room_of_tile.get(start, -1)
	var spots: Array[Vector2i] = []
	for at in _room_of_tile:
		if _room_of_tile[at] == room and _clear_spot(at):
			spots.append(at)
	var route: Array[Vector2] = [_tile_center(start)]
	var want := rng.randi_range(2, 3)
	for i in 30:
		if route.size() > want or spots.is_empty():
			break
		var pick: Vector2i = spots[rng.randi() % spots.size()]
		var at := _tile_center(pick)
		var far_enough := route.all(func(p: Vector2): return p.distance_to(at) >= tile_px * 5.0)
		if far_enough and at.distance_to(route[0]) <= tile_px * 16.0:
			route.append(at)
	return route if route.size() > 1 else [] as Array[Vector2]


## True if a character can stand on this tile: every tile round it is floor
## of a room, and no solid furniture is within 6 px.
func _clear_spot(at: Vector2i) -> bool:
	for y in range(-1, 2):
		for x in range(-1, 2):
			if not _room_of_tile.has(at + Vector2i(x, y)):
				return false
	var body := Rect2(_tile_center(at) - Vector2(6, 6), Vector2(12, 12))
	for rect in _solid_rects:
		if rect.intersects(body):
			return false
	return true


func _room_center(at: Vector2i) -> Vector2:
	var room: int = _room_of_tile.get(at, -1)
	var total := Vector2.ZERO
	var tiles := 0
	for other in _room_of_tile:
		if _room_of_tile[other] == room:
			total += _tile_center(other)
			tiles += 1
	return total / maxf(tiles, 1)


## Builds the walkable map enemies use to find paths around walls.
## Doors are left out on purpose: enemies push through them like you do.
func _build_navigation() -> void:
	var nav_polygon := NavigationPolygon.new()
	nav_polygon.add_outline(PackedVector2Array([
		Vector2.ZERO, Vector2(size_px.x, 0), size_px, Vector2(0, size_px.y),
	]))
	nav_polygon.agent_radius = 8.0
	nav_polygon.parsed_geometry_type = NavigationPolygon.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_polygon.parsed_collision_mask = 1 | WATER_LAYER
	nav_polygon.source_geometry_mode = NavigationPolygon.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nav_polygon.source_geometry_group_name = &"nav_walls"
	var region := NavigationRegion2D.new()
	region.navigation_polygon = nav_polygon
	add_child(region)
	region.bake_navigation_polygon(false)


# ---------------------------------------------------------------- drawing
# Placeholder look until the graphics pass.

## Floor art comes in 16 px squares. With smaller tiles each map tile shows
## its own part of the square covering it, so the pattern stays seamless.
func _draw_floor(canvas: Node2D) -> void:
	if picture:
		canvas.draw_texture(picture, Vector2.ZERO)
		return
	var per := maxi(16 / tile_px, 1)   # map tiles per art square, each way
	for at in _floor_tiles:
		var rect := Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px)
		var room: int = _room_of_tile.get(at, -1)
		if room == -1:   # a doorway: carry on the floor of a room it opens into
			for dir in [Vector2i.DOWN, Vector2i.RIGHT, Vector2i.UP, Vector2i.LEFT]:
				var next: Vector2i = at + dir
				while tile(next) in ["D", "o"]:
					next += dir
				if _room_floor.has(_room_of_tile.get(next, -1)):
					room = _room_of_tile[next]
					break
		var sheet: Texture2D = INTERIORS
		var tint := floor_tint
		var tiles: Array = BRICK_TILES if _brick_rooms.has(room) else WOOD_TILES
		if _room_floor.has(room):
			sheet = FLOORS_PENTHOUSE if _room_floor[room] in PENTHOUSE_FLOORS else FLOORS_V2
			tint = fancy_floor_tint
			tiles = FANCY_FLOORS[_room_floor[room]]
		var square := Vector2i(at.x / per, at.y / per)
		var pick: Rect2 = tiles[(square.x * 7 + square.y * 13) % tiles.size()]
		var part := Vector2(at.x % per, at.y % per) * tile_px
		canvas.draw_texture_rect_region(sheet, rect, Rect2(pick.position + part, Vector2.ONE * mini(tile_px, 16)), tint)
	# No picture yet: plain dark blocks stand in for the furniture.
	for at in _floor_tiles:
		if tile(at) == "x":
			canvas.draw_rect(Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px), Color(0.2, 0.13, 0.1), true)
	# Stairs: dark treads with a light nosing line on each step.
	for at in _floor_tiles:
		if tile(at) != "S":
			continue
		var rect := Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px)
		canvas.draw_rect(rect, Color(0.24, 0.15, 0.1), true)
		var across := tile(at + Vector2i.LEFT) == "S" or tile(at + Vector2i.RIGHT) == "S"
		for i in range(0, tile_px, 3):
			if across:
				canvas.draw_line(rect.position + Vector2(0, i), rect.position + Vector2(tile_px, i), Color(0.62, 0.48, 0.3), 1.0)
			else:
				canvas.draw_line(rect.position + Vector2(i, 0), rect.position + Vector2(i, tile_px), Color(0.62, 0.48, 0.3), 1.0)
	# Marble rooms get a thin gold border a little in from the walls.
	var inset := tile_px * 0.6
	for at in _floor_tiles:
		var room: int = _room_of_tile.get(at, -1)
		if not _room_floor.get(room, "") in ["marble", "dark_marble"]:
			continue
		var corner := Vector2(at) * tile_px
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if tile(at + dir) != "#":
				continue
			var along := Vector2(absi(dir.y), absi(dir.x)) * tile_px   # the edge's length, sideways to dir
			var edge := corner + (Vector2(dir) * 0.5 + Vector2(0.5, 0.5)) * tile_px - Vector2(dir) * inset - along * 0.5
			canvas.draw_line(edge, edge + along, Color(GOLD, 0.7), 1.0)


func _draw_walls(canvas: Node2D) -> void:
	if picture:
		# The walls are in the picture already; draw those parts again on
		# top so blood never paints over a wall or a painting.
		for rect in _walls:
			canvas.draw_texture_rect_region(picture, rect, rect)
		return
	if wall_style == WallStyle.PLASTER:
		_draw_plaster_walls(canvas)
	else:
		for rect in _walls:
			canvas.draw_rect(rect, wall_color.darkened(0.7), true)
		for rect in _walls:
			canvas.draw_rect(rect, Color(wall_color, 0.8), false, 1.0)
	_draw_windows(canvas)


## Window walls: dark glass with a thin frame, a diagonal glint and the odd
## lit city window showing through.
func _draw_windows(canvas: Node2D) -> void:
	for at in _window_tiles:
		var rect := Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px)
		canvas.draw_rect(rect, GLASS.darkened(0.55), true)
		if (at.x * 5 + at.y * 3) % 4 == 0:
			canvas.draw_rect(Rect2(rect.position + Vector2(2, 2), Vector2(2, 2)), Color(1.0, 0.85, 0.45, 0.8), true)
		if (at.x + at.y) % 6 == 0:
			canvas.draw_line(rect.position + Vector2(1, rect.size.y - 1), rect.position + Vector2(rect.size.x - 1, 1), Color(1, 1, 1, 0.35), 1.0)
		for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if _window_tiles.has(at + dir):
				continue
			var along := Vector2(absi(dir.y), absi(dir.x)) * tile_px
			var edge := rect.position + (Vector2(dir) * 0.5 + Vector2(0.5, 0.5)) * tile_px - Vector2(dir) * 0.5 - along * 0.5
			canvas.draw_line(edge, edge + along, Color(0.12, 0.1, 0.1), 1.0)


## The fancy house walls: plaster with a light cap line on each side showing
## the wall's thickness, and red-brick pillars where walls meet or turn and
## on both sides of every doorway.
func _draw_plaster_walls(canvas: Node2D) -> void:
	for rect in _walls:
		canvas.draw_rect(rect, plaster_color, true)
	# Cap lines: along every wall edge that faces an open tile.
	for y in _rows.size():
		for x in _rows[y].length():
			var at := Vector2i(x, y)
			if tile(at) != "#":
				continue
			var corner := Vector2(at) * tile_px
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if tile(at + dir) in ["#", " ", ""]:
					continue
				var along := Vector2(absi(dir.y), absi(dir.x)) * tile_px
				var edge := corner + (Vector2(dir) * 0.5 + Vector2(0.5, 0.5)) * tile_px - Vector2(dir) * 0.5 - along * 0.5
				canvas.draw_line(edge, edge + along, cap_color, 1.0)
	# Pillars.
	for y in _rows.size():
		for x in _rows[y].length():
			var at := Vector2i(x, y)
			if tile(at) != "#":
				continue
			var walls_x := int(tile(at + Vector2i.LEFT) == "#") + int(tile(at + Vector2i.RIGHT) == "#")
			var walls_y := int(tile(at + Vector2i.UP) == "#") + int(tile(at + Vector2i.DOWN) == "#")
			var by_door := false
			for dir in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if tile(at + dir) in ["D", "o"]:
					by_door = true
			if (walls_x > 0 and walls_y > 0) or by_door:
				_draw_pillar(canvas, Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px))


func _draw_pillar(canvas: Node2D, rect: Rect2) -> void:
	var r := rect.grow(0.5)
	canvas.draw_rect(r, brick_color, true)
	var mortar := brick_color.darkened(0.45)
	var h := r.size.y / 3.0
	for i in range(1, 3):
		canvas.draw_line(r.position + Vector2(0, h * i), r.position + Vector2(r.size.x, h * i), mortar, 1.0)
	canvas.draw_line(r.position + Vector2(r.size.x * 0.5, 0), r.position + Vector2(r.size.x * 0.5, h), mortar, 1.0)
	canvas.draw_line(r.position + Vector2(r.size.x * 0.3, h * 2), r.position + Vector2(r.size.x * 0.3, r.size.y), mortar, 1.0)
	canvas.draw_rect(r, brick_color.lightened(0.25), false, 1.0)

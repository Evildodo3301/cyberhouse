class_name LevelMap
extends Node2D
## Builds a whole level from a text map, so a level can be changed by
## editing letters instead of placing nodes by hand. One letter = one tile
## (tile_px square; 8 px gives thin walls, 16 px = one character width):
##
##   #  wall              .  floor
##   (space)  open sky: you can't go there, and the neon void shows through
##   D  swinging door     o  open doorway (no door)
##      (a straight run of D's or o's in a wall = one doorway)
##   P  player start      g  pistol on the floor
##   m  machete on the floor
##   C  cop grunt with a pistol: shoots you, drops the pistol
##   M  cop grunt with a machete (drops it)    F  cop grunt, fists only
##   G  cop grunt with a machine gun: fires bursts, drops it
##   u  machine gun on the floor
##   V  civilian grunt with a pistol (looks like a cop for now, so the
##      player is the only one in pink; shoots, drops the pistol)
##   E  exit (opens once every enemy is dead)
##
## Rooms are worked out automatically: floor areas separated by walls and
## doorways. Enemies notice you the moment you step into their room.
##
## Furniture goes in a second list, one item per line: "sofa 17 1" puts a
## sofa with its top-left corner on tile (17, 1). "floor_brick 5 5" gives
## the room around tile (5, 5) a brick floor; "floor_marble",
## "floor_dark_marble" and "floor_bath" give it a fancy floor; other
## rooms get wood. Solid pieces block you,
## enemies and bullets (enemies path round them); rugs are floor decoration.
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
}
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

## Size of the level in pixels.
var size_px: Vector2
var _rows: PackedStringArray
var _room_of_tile: Dictionary = {}   # Vector2i -> room index
var _walls: Array[Rect2] = []
var _floor_tiles: Array[Vector2i] = []
var _brick_rooms: Dictionary = {}   # room index -> true
var _room_floor: Dictionary = {}    # room index -> "marble", "dark_marble" or "bath"


func _ready() -> void:
	add_to_group("level")   # enemies ask it which room a point is in
	_rows = layout.strip_edges().split("\n")
	var width := 0
	for row in _rows:
		width = maxi(width, row.length())
	size_px = Vector2(width, _rows.size()) * tile_px
	_find_rooms()
	_build_walls()
	_build_doorways()
	_place_gang_rugs()
	_place_furniture()
	_spawn_things()
	_build_navigation()
	var floor_drawer := Node2D.new()
	floor_drawer.z_index = -2   # under the rugs and the blood
	floor_drawer.draw.connect(_draw_floor.bind(floor_drawer))
	add_child(floor_drawer)
	var wall_drawer := Node2D.new()
	wall_drawer.z_index = 1     # walls cover any blood that splashes onto them
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
	return not letter in ["#", "D", "o", " "]


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
			if letter != "#" and letter != " ":
				x += 1
				continue
			var start := x
			while x < _rows[y].length() and tile(Vector2i(x, y)) == letter:
				x += 1
			var rect := Rect2(start * tile_px, y * tile_px, (x - start) * tile_px, tile_px)
			if letter == "#":
				_walls.append(rect)
			var body := StaticBody2D.new()
			body.collision_layer = 1   # layer 1 = "world"
			body.collision_mask = 0
			body.add_to_group("nav_walls")   # enemies' pathfinding avoids these
			body.position = rect.get_center()
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = rect.size
			shape.shape = rectangle
			body.add_child(shape)
			add_child(body)


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
		piece.position = Vector2(int(parts[1]), int(parts[2])) * tile_px
		if parts[0].ends_with("rug") or parts[0].begins_with("rug_"):
			piece.z_index = -1   # rugs: on the floor, under the blood
		add_child(piece)
		if solid:
			var body := StaticBody2D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.add_to_group("nav_walls")
			body.position = piece.position + region.size * 0.5
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = region.size - Vector2(2, 2)
			shape.shape = rectangle
			body.add_child(shape)
			add_child(body)


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
			count += 1
			var door: Node2D = DOOR_SCENE.instantiate()
			door.name = "Door%d" % count
			door.door_id = door.name
			door.length = length * tile_px
			if step == Vector2i.RIGHT:
				door.position = Vector2(at.x * tile_px, at.y * tile_px + tile_px * 0.5)
			else:
				door.position = Vector2(at.x * tile_px + tile_px * 0.5, at.y * tile_px)
				door.rotation = PI * 0.5
			add_child(door)


func _spawn_things() -> void:
	var count := {"C": 0, "V": 0, "M": 0, "F": 0, "G": 0, "g": 0, "m": 0, "u": 0}
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
			"C", "V", "M", "F", "G":
				count[letter] += 1
				var grunt: Node2D = GRUNT_SCENE.instantiate()
				grunt.name = {"C": "Cop%d", "V": "Civilian%d", "M": "Thug%d", "F": "Brawler%d", "G": "Gunner%d"}[letter] % count[letter]
				grunt.position = spot
				if letter == "M":
					grunt.carried_weapon = MACHETE
				elif letter == "G":
					grunt.carried_weapon = MACHINE_GUN
				elif letter == "F":
					grunt.carried_weapon = null   # fists only, drops nothing
				# Every 1/roam_chance-th enemy (in map order) is a roamer.
				var index: int = count["C"] + count["V"] + count["M"] + count["F"] + count["G"]
				grunt.stays_in_room = floori(index * roam_chance) == floori((index - 1) * roam_chance)
				grunt.start_facing_degrees = rad_to_deg(spot.angle_to_point(_room_center(at)))
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
		add_child(exit_zone)


## The middle of the room a tile belongs to (guards face into their room).
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
	nav_polygon.parsed_collision_mask = 1
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
	var per := maxi(16 / tile_px, 1)   # map tiles per art square, each way
	for at in _floor_tiles:
		var rect := Rect2(Vector2(at) * tile_px, Vector2.ONE * tile_px)
		var room: int = _room_of_tile.get(at, -1)   # doorways get the wood floor
		var sheet: Texture2D = INTERIORS
		var tint := floor_tint
		var tiles: Array = BRICK_TILES if _brick_rooms.has(room) else WOOD_TILES
		if _room_floor.has(room):
			sheet = FLOORS_V2
			tint = fancy_floor_tint
			tiles = FANCY_FLOORS[_room_floor[room]]
		var square := Vector2i(at.x / per, at.y / per)
		var pick: Rect2 = tiles[(square.x * 7 + square.y * 13) % tiles.size()]
		var part := Vector2(at.x % per, at.y % per) * tile_px
		canvas.draw_texture_rect_region(sheet, rect, Rect2(pick.position + part, Vector2.ONE * mini(tile_px, 16)), tint)
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
	if wall_style == WallStyle.PLASTER:
		_draw_plaster_walls(canvas)
		return
	for rect in _walls:
		canvas.draw_rect(rect, wall_color.darkened(0.7), true)
	for rect in _walls:
		canvas.draw_rect(rect, Color(wall_color, 0.8), false, 1.0)


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

class_name LevelMap
extends Node2D
## Builds a whole level from a text map, so a level can be changed by
## editing letters instead of placing nodes by hand. One letter = one tile
## (16 x 16 px, one character width):
##
##   #  wall              .  floor
##   D  swinging door     o  open doorway (no door)
##      (a straight run of D's or o's in a wall = one doorway)
##   P  player start      g  pistol on the floor
##   C  cop grunt         V  civilian grunt
##   E  exit (opens once every enemy is dead)
##
## Rooms are worked out automatically: floor areas separated by walls and
## doorways. Enemies notice you the moment you step into their room.

const TILE := 16
const GRUNT_SCENE := preload("res://scenes/enemies/grunt.tscn")
const DOOR_SCENE := preload("res://scenes/props/swing_door.tscn")
const PICKUP_SCENE := preload("res://scenes/weapons/weapon_pickup.tscn")
const CIVILIAN_SHEET := preload("res://assets/characters/civilian.png")
const EXIT_SCRIPT := preload("res://scripts/levels/exit_zone.gd")

@export_multiline var layout: String = ""
@export var wall_color: Color = Color(0.55, 0.2, 1.0)    # neon purple
@export var floor_color: Color = Color(0.03, 0.02, 0.06)
@export var grid_color: Color = Color(0.2, 0.1, 0.35, 0.6)

## Size of the level in pixels.
var size_px: Vector2
var _rows: PackedStringArray
var _room_of_tile: Dictionary = {}   # Vector2i -> room index
var _walls: Array[Rect2] = []
var _floor_tiles: Array[Vector2i] = []


func _ready() -> void:
	add_to_group("level")   # enemies ask it which room a point is in
	_rows = layout.strip_edges().split("\n")
	var width := 0
	for row in _rows:
		width = maxi(width, row.length())
	size_px = Vector2(width, _rows.size()) * TILE
	_find_rooms()
	_build_walls()
	_build_doorways()
	_spawn_things()
	_build_navigation()
	var floor_drawer := Node2D.new()
	floor_drawer.z_index = -1   # under the blood
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
	return (Vector2(at) + Vector2(0.5, 0.5)) * TILE


## Which room `point` is in, or -1 for walls and doorways.
func room_at(point: Vector2) -> int:
	return _room_of_tile.get(Vector2i((point / TILE).floor()), -1)


func room_count() -> int:
	var rooms := {}
	for room in _room_of_tile.values():
		rooms[room] = true
	return rooms.size()


# ------------------------------------------------------------------ build

func _is_open(letter: String) -> bool:
	return letter != "#" and letter != "D" and letter != "o"


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


## One wall body per horizontal run of "#", to keep the physics cheap.
func _build_walls() -> void:
	for y in _rows.size():
		var x := 0
		while x < _rows[y].length():
			if tile(Vector2i(x, y)) != "#":
				x += 1
				continue
			var start := x
			while tile(Vector2i(x, y)) == "#" and x < _rows[y].length():
				x += 1
			var rect := Rect2(start * TILE, y * TILE, (x - start) * TILE, TILE)
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
			door.length = length * TILE
			if step == Vector2i.RIGHT:
				door.position = Vector2(at.x * TILE, at.y * TILE + TILE * 0.5)
			else:
				door.position = Vector2(at.x * TILE + TILE * 0.5, at.y * TILE)
				door.rotation = PI * 0.5
			add_child(door)


func _spawn_things() -> void:
	var count := {"C": 0, "V": 0, "g": 0}
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
			"C", "V":
				count[letter] += 1
				var grunt: Node2D = GRUNT_SCENE.instantiate()
				grunt.name = ("Cop%d" if letter == "C" else "Civilian%d") % count[letter]
				grunt.position = spot
				if letter == "V":
					grunt.sheet = CIVILIAN_SHEET
					grunt.sheet_rows = 2
				grunt.start_facing_degrees = rad_to_deg(spot.angle_to_point(_room_center(at)))
				add_child(grunt)
			"g":
				count["g"] += 1
				var pickup: Node2D = PICKUP_SCENE.instantiate()
				pickup.name = "Pistol%d" % count["g"]
				pickup.position = spot
				add_child(pickup)
			"E":
				pass
	# The exit: one zone covering every E tile.
	var exit_rect := Rect2()
	for at in _floor_tiles:
		if tile(at) == "E":
			var tile_rect := Rect2(Vector2(at) * TILE, Vector2.ONE * TILE)
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

func _draw_floor(canvas: Node2D) -> void:
	for at in _floor_tiles:
		var rect := Rect2(Vector2(at) * TILE, Vector2.ONE * TILE)
		canvas.draw_rect(rect, floor_color)
		canvas.draw_rect(rect, grid_color, false, 1.0)


func _draw_walls(canvas: Node2D) -> void:
	for rect in _walls:
		canvas.draw_rect(rect, wall_color.darkened(0.7), true)
	for rect in _walls:
		canvas.draw_rect(rect, Color(wall_color, 0.8), false, 1.0)

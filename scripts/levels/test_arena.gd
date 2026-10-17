extends Node2D
## A simple walled room for testing movement and attacks.
## The walls are built by code from the list below, so you can change the
## room by editing numbers instead of drawing it by hand.

## Room size in pixels (30 x 20 character widths).
@export var room_size: Vector2 = Vector2(480, 320)
## Extra walls inside the room, as Rect2(x, y, width, height).
@export var pillars: Array[Rect2] = [
	Rect2(120, 80, 32, 32),
	Rect2(320, 200, 48, 24),
	Rect2(220, 140, 16, 64),
]
@export var wall_thickness: float = 16.0
@export var wall_color: Color = Color(0.55, 0.2, 1.0)    # neon purple
@export var grid_color: Color = Color(0.2, 0.1, 0.35, 0.6)

var _walls: Array[Rect2] = []


func _ready() -> void:
	var t := wall_thickness
	_walls = [
		Rect2(-t, -t, room_size.x + 2 * t, t),       # top
		Rect2(-t, room_size.y, room_size.x + 2 * t, t), # bottom
		Rect2(-t, 0, t, room_size.y),                # left
		Rect2(room_size.x, 0, t, room_size.y),       # right
	]
	_walls.append_array(pillars)
	for rect in _walls:
		_add_wall(rect)
	# Walls are drawn by a separate child that sits above the blood layer,
	# so gore lands on the floor but never on top of a wall.
	var wall_drawer := Node2D.new()
	wall_drawer.z_index = 1
	wall_drawer.draw.connect(_draw_walls.bind(wall_drawer))
	add_child(wall_drawer)


## Creates one solid wall: a StaticBody2D with a rectangle collision shape.
func _add_wall(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1   # layer 1 = "world"
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = rect.size
	shape.shape = rectangle
	body.add_child(shape)
	add_child(body)


func _draw() -> void:
	# Floor grid only (walls are drawn by _draw_walls).
	for x in range(0, int(room_size.x) + 1, 16):
		draw_line(Vector2(x, 0), Vector2(x, room_size.y), grid_color, 1.0)
	for y in range(0, int(room_size.y) + 1, 16):
		draw_line(Vector2(0, y), Vector2(room_size.x, y), grid_color, 1.0)


func _draw_walls(canvas: Node2D) -> void:
	for rect in _walls:
		canvas.draw_rect(rect, wall_color.darkened(0.7), true)
		canvas.draw_rect(rect, wall_color, false, 1.0)

class_name Stairs
extends Node2D
## A staircase between two floors of the same level. Both floors are drawn
## in one map, far apart; walking onto one end of the stairs puts you on the
## other end, on the other floor. Step off the stairs before you can take
## them back (so you don't bounce up and down).
##
## Made by LevelMap from a "stairs x1 y1 x2 y2" line; nothing else needs to
## create one.

signal taken(to_floor: int)

## The two ends, in map coordinates, and the floor each end is on.
var ends: Array[Rect2] = []
var floors: Array[int] = []

var _ready_to_use: bool = true


func _ready() -> void:
	add_to_group("stairs")


func _physics_process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.is_alive():
		return
	var here := to_local(player.global_position)
	var on := -1
	for i in ends.size():
		if ends[i].has_point(here):
			on = i
	if on == -1:
		_ready_to_use = true
		return
	if not _ready_to_use:
		return
	var other := 1 - on
	_ready_to_use = false
	player.global_position = to_global(ends[other].get_center())
	player.velocity = Vector2.ZERO
	var camera := get_viewport().get_camera_2d()
	if camera:
		camera.global_position = player.global_position
		camera.reset_smoothing()
	taken.emit(floors[other])

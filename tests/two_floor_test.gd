extends SceneTree
## Checks two floors in one level: stairs take you up and back down, the
## floor banner shows, and enemies stay on their own floor.
##   godot --headless --script res://tests/two_floor_test.gd

const LAYOUT := """
##############
#............#
#..M.........#
#.........SS.#
#.........SS.#
##############




##############
#............#
#.P.......SS.#
#.........SS.#
#.......E....#
##############
"""

var failures := 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	root.get_node("TacticTracker").clear_room(&"two_floor_test")
	var level: Node2D = load("res://scenes/levels/level_01.tscn").instantiate()
	level.room_id = &"two_floor_test"
	level.next_level = ""
	var map = level.get_node("LevelMap")
	map.layout = LAYOUT
	map.picture = null   # a plain drawn house, not level 1's picture
	map.picture_pieces = ""
	map.furniture = "stairs 10 3 10 12\nfloor_marble 3 2\nfloor_checker 3 12"
	level.get_node("Gore").area_size = Vector2i(112, 128)
	root.add_child(level)
	current_scene = level
	await wait_frames(3)
	var player = level.get_node("Player")
	var thug = map.find_child("Thug1", true, false)
	var stairs: Array = get_nodes_in_group("stairs")

	check(map.storey_count() == 2, "the map has two floors")
	check(map.storey_at(player.global_position) == 2 and map.storey_at(thug.global_position) == 1, "you start on floor 2 (bottom of the map), the thug is on floor 1")
	check(stairs.size() == 1 and stairs[0].floors == [1, 2], "one staircase joins floor 1 and floor 2")
	var nav_map: RID = player.get_world_2d().navigation_map
	await wait_frames(2)
	var path := NavigationServer2D.map_get_path(nav_map, thug.global_position, player.global_position, true)
	check(path.size() == 0 or path[path.size() - 1].distance_to(player.global_position) > 12.0, "enemies can't walk to the other floor")

	# Walk onto the stairs: you come out on the other floor.
	thug.set_physics_process(false)
	var banner := []
	map.floor_changed.connect(func(storey): banner.append(storey))
	player.global_position = (Vector2(10.5, 12.5)) * 8.0
	await wait_frames(2)
	check(map.storey_at(player.global_position) == 1, "the stairs take you up to floor 1")
	check(banner == [1], "a FLOOR 1 banner shows")
	await wait_frames(10)
	check(map.storey_at(player.global_position) == 1, "you don't bounce straight back down while standing on the stairs")
	var camera := root.get_viewport().get_camera_2d()
	check(camera.global_position.distance_to(player.global_position) < 40.0, "the camera comes with you")
	# Step off and back on: down again.
	player.global_position = Vector2(4.5, 3.5) * 8.0
	await wait_frames(2)
	player.global_position = Vector2(10.5, 3.5) * 8.0
	await wait_frames(2)
	check(map.storey_at(player.global_position) == 2 and banner == [1, 2], "step off and on again: back down to floor 2")

	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)

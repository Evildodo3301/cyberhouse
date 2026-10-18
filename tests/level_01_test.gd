extends SceneTree
## Checks level 1 is built correctly from its text map and can be finished.
##   godot --headless --script res://tests/level_01_test.gd

var failures := 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	root.get_node("TacticTracker").clear_room(&"level_01")
	change_scene_to_file("res://scenes/levels/level_01.tscn")
	await process_frame
	await process_frame
	await wait_frames(3)
	var level = current_scene
	var map = level.get_node("LevelMap")
	var player = level.get_node("Player")
	var enemies: Array = root.get_tree().get_nodes_in_group("enemies")
	check(map.room_count() == 6, "6 rooms")
	check(enemies.size() == 9, "9 enemies")
	check(root.get_tree().get_nodes_in_group("doors").size() == 5, "5 swinging doors")
	check(root.get_tree().get_nodes_in_group("pickups").size() == 2, "2 pistols placed")
	check(player.weapon.id == &"fists", "you start unarmed")
	var start_room: int = map.room_at(player.global_position)
	check(start_room >= 0 and enemies.all(func(e): return map.room_at(e.global_position) != start_room), "the start room is safe")
	var exit_zone = root.get_tree().get_first_node_in_group("exit")
	check(exit_zone != null and not exit_zone.open, "exit exists and is locked")

	# Every enemy can walk to you (paths through doors and doorways).
	var nav_map: RID = player.get_world_2d().navigation_map
	await wait_frames(2)
	var reachable := enemies.all(func(e):
		var path := NavigationServer2D.map_get_path(nav_map, e.global_position, player.global_position, true)
		return path.size() > 0 and path[path.size() - 1].distance_to(player.global_position) < 12.0)
	check(reachable, "every enemy has a path to the start")

	# Step into the first room: its civilian notices you at once.
	var top_left := Vector2(3 * 16 + 8, 10 * 16 + 8)
	var civilian = enemies.filter(func(e): return map.room_at(e.global_position) == map.room_at(top_left))[0]
	player.global_position = top_left
	await wait_frames(3)
	check(civilian.state == 1, "entering a room alerts its enemy")

	# Kill everyone: the exit opens; walk in: LEVEL COMPLETE.
	player.global_position = Vector2(3 * 16 + 8, 20 * 16 + 8)
	for enemy in root.get_tree().get_nodes_in_group("enemies"):
		enemy.take_hit(player, Vector2.RIGHT, "melee")
	await wait_frames(2)
	check(exit_zone.open, "all enemies dead: the exit opens")
	player.global_position = exit_zone.rect.get_center()
	await wait_frames(3)
	var death_screen = level.get_node("DeathScreen")
	check(death_screen.visible and "LEVEL COMPLETE" in death_screen._label.text, "reaching the exit completes the level")

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

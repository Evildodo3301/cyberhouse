extends SceneTree
## Checks the penthouse (level 2): window walls, wall decor, the new floors,
## double doors, depth sorting and furniture footprints.
##   godot --headless --script res://tests/level_02_test.gd

var failures := 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	root.get_node("TacticTracker").clear_room(&"level_02")
	change_scene_to_file("res://scenes/levels/level_02.tscn")
	await process_frame
	await process_frame
	await wait_frames(3)
	var level = current_scene
	var map = level.get_node("LevelMap")
	var player = level.get_node("Player")
	var enemies: Array = root.get_tree().get_nodes_in_group("enemies")
	var doors: Array = root.get_tree().get_nodes_in_group("doors")
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var t := func(x: int, y: int) -> Vector2: return (Vector2(x, y) + Vector2(0.5, 0.5)) * 8.0
	var solid_at := func(at: Vector2) -> bool:
		var q := PhysicsPointQueryParameters2D.new()
		q.position = at
		q.collision_mask = 1
		return not space.intersect_point(q).is_empty()

	check(map.room_count() == 8, "8 rooms: kitchen, dining and bar, master suite, bath, office, living, gallery, foyer (%d)" % map.room_count())
	check(enemies.size() == 12 and enemies.filter(func(e): return e.is_dog).size() == 2, "12 enemies, 2 of them dobermans (%d)" % enemies.size())
	check(level.next_level == "" and level.y_sort_enabled and map.y_sort_enabled, "depth sorting is on for the level and the map")
	check(root.get_tree().get_first_node_in_group("exit") != null, "the penthouse has an exit")

	# Window walls block like walls and are drawn as glass.
	check(map._window_tiles.size() > 60, "floor-to-ceiling windows on the north and east (%d tiles)" % map._window_tiles.size())
	check(map.tile(Vector2i(40, 0)) == "#" and solid_at.call(t.call(40, 0)), "a window blocks like a wall")

	# Floors: checker kitchen, parquet living room.
	check(map._room_floor.get(map.room_at(t.call(10, 10))) == "checker", "the kitchen has the black and white checker floor")
	check(map._room_floor.get(map.room_at(t.call(60, 50))) == "herringbone", "the living room has the dark wood parquet")
	check(map._room_floor.get(map.room_at(t.call(60, 70))) == "marble", "the foyer has marble")

	# Double doors: 8 D's = two half doors meeting in the middle.
	check(doors.size() == 7, "3 single doors and 2 double doors = 7 door panels (%d)" % doors.size())
	var halves := doors.filter(func(d): return d.length == 32.0)
	check(halves.size() == doors.size(), "every door panel is 32 px")
	var office_pair := doors.filter(func(d): return d.global_position.distance_to(t.call(32, 48) - Vector2(0, 4)) < 40.0 and absf(d.global_position.x - 260.0) < 1.0)
	check(office_pair.size() == 2 and office_pair[0].center().distance_to(office_pair[1].center()) <= 32.0, "the office double door: two halves hinged at both ends")

	# Wall decor hangs on walls, above everything that walks.
	var decor: Array = root.get_tree().get_nodes_in_group("wall_decor")
	check(decor.size() >= 15, "paintings, sconces and clocks on the walls (%d)" % decor.size())
	check(decor.all(func(d): return d.z_index == 2 and map.tile(Vector2i(d.global_position / 8.0)) == "#"), "all decor sits on wall tiles, drawn over the walls")
	var side_painting = decor.filter(func(d): return absf(d.rotation) > 1.0 and absf(d.rotation) < 2.0)
	check(not side_painting.is_empty(), "decor on side walls is turned to face the room")
	check(decor.all(func(d): return not solid_at.call(d.global_position) or map.tile(Vector2i(d.global_position / 8.0)) == "#"), "decor adds no collision of its own")

	# Furniture: base at the node position (for Y-sorting), footprints.
	var plants: Array = map.get_children().filter(func(c): return c is Sprite2D and c.is_in_group("fancy_furniture") and c.texture.resource_path.ends_with("/plant.png"))
	check(plants.size() >= 6 and plants.all(func(p): return p.offset.y == -p.texture.get_size().y), "furniture stands at its base, so lower things draw in front")
	var plant = plants[0]
	var corner: Vector2 = plant.position + plant.offset
	check(solid_at.call(corner + Vector2(6, 6)) and not solid_at.call(corner + Vector2(1, 1)), "a plant only blocks at its pot, not its leaves")
	var sofa = map.get_children().filter(func(c): return c is Sprite2D and c.is_in_group("fancy_furniture") and c.texture.resource_path.ends_with("/white_sofa_long.png"))[0]
	var sofa_corner: Vector2 = sofa.position + sofa.offset
	check(solid_at.call(sofa_corner + Vector2(3, 3)) and solid_at.call(sofa_corner + sofa.texture.get_size() - Vector2(3, 3)), "a sofa blocks with its whole shape")

	# Every enemy can reach you, and furniture never blocks spawns or door swings.
	await wait_frames(2)
	player.global_position = t.call(58, 70)
	var nav_map: RID = player.get_world_2d().navigation_map
	await wait_frames(2)
	var stuck := enemies.filter(func(e):
		var path := NavigationServer2D.map_get_path(nav_map, e.global_position, player.global_position, true)
		return path.size() == 0 or path[path.size() - 1].distance_to(player.global_position) >= 12.0).map(func(e): return e.name)
	check(stuck.is_empty(), "every enemy has a path to the start %s" % [stuck])
	var pickups: Array = root.get_tree().get_nodes_in_group("pickups")
	var spots: Array = enemies.map(func(e): return e.global_position) + pickups.map(func(p): return p.global_position)
	var blocked := spots.filter(func(at): return solid_at.call(at))
	check(blocked.is_empty(), "no spawn or weapon sits inside furniture %s" % [blocked])
	var solids := map.get_children().filter(func(c): return c is StaticBody2D and c.is_in_group("nav_walls") and map.tile(Vector2i(c.position / map.tile_px)) != "#")
	var in_swing := solids.filter(func(b): return doors.any(func(d): return (b.global_position - d.center()).length() < d.length * 0.75))
	check(in_swing.is_empty(), "no furniture in a door's swing %s" % [in_swing.map(func(b): return Vector2i(b.position / 8.0))])
	var start_room: int = map.room_at(player.global_position)
	check(enemies.all(func(e): return map.room_at(e.global_position) != start_room), "the foyer you start in is safe")

	print("ALL PASSED" if failures == 0 else "%d FAILED" % failures)
	quit(failures)

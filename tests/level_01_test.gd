extends SceneTree
## Checks level 1, floor 1 of the mansion: built from Fianso's picture
## (the drawing is the floor, the furniture is cut out and stands on it),
## and that it plays: patrols, sneaking, doors, weapons, shots and kills.
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
	var t := func(x: int, y: int) -> Vector2: return (Vector2(x, y) + Vector2(0.5, 0.5)) * 8.0   # tile centre
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var blocks := func(at: Vector2, mask: int) -> bool:
		var q := PhysicsPointQueryParameters2D.new()
		q.position = at
		q.collision_mask = mask
		return not space.intersect_point(q).is_empty()

	# Built from the picture.
	check(map.picture != null and map.picture.get_size() == Vector2(736, 424), "the floor is Fianso's picture (736 x 424 px)")
	var pieces: Array = root.get_tree().get_nodes_in_group("picture_pieces")
	check(pieces.size() == 40, "40 pieces of furniture cut out of it (%d)" % pieces.size())
	var data = load(map.picture_pieces).data
	var sofa: Dictionary = data.pieces.filter(func(p): return p.name == "sofa_top")[0]
	var sofa_node = pieces.filter(func(p): return p.name == "SofaTop")[0]
	check(sofa_node.position.y == sofa.sort_y and sofa_node.position.y + sofa_node.offset.y == sofa.y, "furniture stands at its base, so whoever is lower down is drawn in front")
	var box := Rect2(sofa.collision[0], sofa.collision[1], sofa.collision[2], sofa.collision[3])
	check(blocks.call(box.get_center(), 1) and not blocks.call(Vector2(sofa.x + 2, sofa.y + 2), 1), "the sofa blocks at its seat, not at the top of its back")
	check(root.get_tree().get_nodes_in_group("rugs").is_empty(), "no gang rugs: the picture has its own")
	var pool_tile := Vector2i(70, 5)
	check(map.tile(pool_tile) == "~" and blocks.call(t.call(70, 5), 32) and not blocks.call(t.call(70, 5), 1 | 16), "the pool stops feet but not bullets")
	check(blocks.call(Vector2(-4, 20), 1) and blocks.call(Vector2(20, map.size_px.y + 4), 1), "you can't walk off the edge of the map")
	var doors := root.get_tree().get_nodes_in_group("doors")
	check(doors.size() == 5, "kitchen, office (2) and the terrace double door (2 leaves) = 5 door panels (%d)" % doors.size())
	var terrace := doors.filter(func(d): return d.one_way != 0.0)
	check(terrace.size() == 2, "the terrace door only swings out")

	# Who is where (the Level Designer's placements).
	var dogs := enemies.filter(func(e): return e.is_dog)
	check(enemies.size() == 5 and dogs.size() == 1, "an easy floor: 4 people and a doberman (%d)" % enemies.size())
	check(player.global_position == t.call(45, 48) and player.weapon.id == &"fists", "you start unarmed on the front steps")
	var pickups := root.get_tree().get_nodes_in_group("pickups")
	check(pickups.size() == 2, "a machete by the door and a pistol in the kitchen")
	var by_tile := func(x: int, y: int): return enemies.filter(func(e): return e._home == t.call(x, y))[0]
	check(Array(by_tile.call(55, 38).patrol_points) == [t.call(55, 38), t.call(55, 19)], "the lounge guard walks up and down the lounge")
	check(by_tile.call(66, 36).patrol_points.size() == 4, "the doberman walks a loop in the office")
	check(is_equal_approx(by_tile.call(12, 21).start_facing_degrees, 180.0), "the cook faces west, his back to the lounge")
	check(is_equal_approx(by_tile.call(75, 18).start_facing_degrees, 90.0) and by_tile.call(75, 18).has_gun(), "the boss sits behind the desk with a pistol, facing south")
	check(enemies.all(func(e): return e.settings.reaction_time >= 0.35 and not e.settings.notice_whole_room), "enemies only see in front of them, and react slowly")

	# Everyone can reach you; nothing starts inside furniture.
	var nav_map: RID = player.get_world_2d().navigation_map
	await wait_frames(2)
	var stuck := enemies.filter(func(e):
		var path := NavigationServer2D.map_get_path(nav_map, e.global_position, player.global_position, true)
		return path.size() == 0 or path[path.size() - 1].distance_to(player.global_position) >= 12.0).map(func(e): return e.name)
	check(stuck.is_empty(), "every enemy has a path to you %s" % [stuck])
	var spots: Array = enemies.map(func(e): return e.global_position) + pickups.map(func(p): return p.global_position)
	check(spots.filter(func(at): return blocks.call(at, 1 | 32)).is_empty(), "no enemy or weapon starts inside furniture")

	# Sneaking: the cook doesn't hear you creep up behind him.
	var cook = by_tile.call(12, 21)
	player.global_position = t.call(16, 21)   # 32 px behind him
	await wait_frames(20)
	check(cook.state == 0, "you can stand right behind the cook")
	player.request_attack(Vector2.LEFT)
	for i in 6:
		player.global_position = player.global_position.move_toward(cook.global_position + Vector2(14, 0), 4.0)
		await physics_frame
	player.request_attack(Vector2.LEFT)
	await wait_frames(20)
	check(not cook.is_alive(), "sneak up behind him and take him out")
	var boss = by_tile.call(75, 18)
	for e in enemies:
		if e != boss:
			e.set_physics_process(false)
	player.global_position = t.call(75, 22)   # right in front of the desk
	await wait_frames(3)
	check(boss.state in [1, 2, 7], "step in front of the boss and he notices you")
	player.global_position = t.call(45, 48)
	boss.take_hit(player, Vector2.DOWN, "melee")
	await wait_frames(10)

	# Doors: opening one only alerts an enemy looking at it.
	var guard = load("res://scenes/enemies/grunt.tscn").instantiate()
	guard.settings = load("res://data/easy_grunt_settings.tres")
	guard.position = t.call(62, 25)   # in the office, clear view of the door
	var to_door: Vector2 = (Vector2(484, 168) - guard.position).normalized()
	guard.start_facing_degrees = rad_to_deg((-to_door).angle())   # back to the office door
	map.add_child(guard)
	await wait_frames(2)
	player.global_position = Vector2(478, t.call(0, 19).y)
	await wait_frames(4)
	check(guard.state == 0, "the office door opening behind an enemy's back goes unnoticed")
	player.global_position = t.call(45, 40)
	await wait_frames(60)
	guard._home_facing = to_door
	guard.facing = to_door
	player.global_position = Vector2(478, t.call(0, 19).y)
	await wait_frames(4)
	check(guard.state in [1, 2], "an enemy watching the door reacts when it opens")
	guard.take_hit(player, Vector2.RIGHT, "melee")
	player.global_position = t.call(45, 48)
	await wait_frames(30)

	# Weapons: walk onto the machete, then onto a pistol: you switch each time,
	# and what you held drops at your feet (and isn't grabbed straight back).
	for e in enemies:
		e.set_physics_process(false)   # nobody interrupts the weapon checks
	var machete = pickups.filter(func(p): return p.weapon.id == &"machete")[0]
	player.global_position = machete.global_position
	await wait_frames(3)
	check(player.weapon.id == &"machete", "walking onto a machete picks it up")
	check(player.weapon.reach > load("res://data/weapons/fists.tres").reach, "the machete reaches further than fists")
	var pistol = pickups.filter(func(p): return is_instance_valid(p) and p.weapon.id == &"pistol")[0]
	player.global_position = pistol.global_position
	await wait_frames(4)
	check(player.weapon.id == &"pistol" and player.ammo == 8, "walking onto a pistol switches to it")
	await wait_frames(30)
	var dropped := root.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.weapon.id == &"machete" and p.global_position.distance_to(player.global_position) < 40.0)
	var toss: float = dropped[0].global_position.distance_to(player.global_position) if dropped.size() == 1 else 0.0
	check(dropped.size() == 1 and toss > 18.0, "the machete you held is tossed about a metre away (%.0f px)" % toss)
	check(player.weapon.id == &"pistol", "it isn't picked straight back up")
	# A machete thug drops his machete.
	var thug = enemies.filter(func(e): return e.carried_weapon and e.carried_weapon.id == &"machete")[0]
	thug.take_hit(player, Vector2.RIGHT, "melee")
	await wait_frames(30)
	var thug_drop := root.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.weapon.id == &"machete" and p.global_position.distance_to(thug.global_position) < 60.0)
	check(thug_drop.size() == 1, "a machete enemy drops a machete on the floor")
	player.equip(load("res://data/weapons/fists.tres"), -1)
	for e in enemies:
		e.set_physics_process(true)

	# Shoot: a tiny triple kick, and the void flashes neon then fades.
	player.global_position = t.call(45, 48)
	player.equip(load("res://data/weapons/pistol.tres"), 8)
	var camera = level.get_node("GameCamera")
	var void_flash = level.get_node("VoidFlash")
	player.request_attack(Vector2.LEFT)
	await wait_frames(1)
	check(camera._kicks.size() >= 2, "a shot kicks the camera in quick steps")
	var biggest := 0.0
	for k in camera._kicks:
		biggest = maxf(biggest, k.length())
	check(biggest >= 2.0 and biggest <= 6.0, "the kick is about 2%% of the screen (%.1f px)" % biggest)
	check(player._muzzle_light.visible, "a shot lights a circle around you")
	await process_frame
	check(void_flash.strength > 0.0 and RenderingServer.get_default_clear_color() != void_flash._base, "the void flashes on a shot")
	await create_timer(1.0).timeout
	check(camera._kicks.is_empty(), "the kick is over quickly")
	check(void_flash.strength == 0.0, "the void flash fades out")

	# Kills: the void jumps to a new colour, "+points" pop up, quick kills chain a combo.
	var score_board = level.get_node("ScoreBoard")
	while score_board.combo > 0:   # let the machete thug's chain run out
		await process_frame
	var victims := enemies.filter(func(e): return e.is_alive())
	var hue_before: float = void_flash.hue
	var score_before: int = score_board.score   # the machete thug already scored
	victims[0].take_hit(player, Vector2.RIGHT, "melee")
	var jump := absf(fposmod(void_flash.hue - hue_before + 0.5, 1.0) - 0.5)
	check(jump >= 0.2, "a kill makes the void jump to a new colour (%.2f of the wheel)" % jump)
	check(void_flash.glow > 0.9, "the void glows brighter right after a kill")
	check(score_board.score - score_before == 400 and score_board._popups.size() == 1, "a kill scores 400 and pops up \"+400\"")
	victims[1].take_hit(player, Vector2.RIGHT, "melee")
	await process_frame
	check(score_board.combo == 2 and score_board.score - score_before == 1200 and score_board._combo_label.visible, "a quick second kill is a x2 combo (+800)")
	await create_timer(score_board.combo_window + 0.2).timeout
	check(score_board.combo == 0 and not score_board._combo_label.visible, "the combo breaks after a pause")
	check(score_board._popups.is_empty(), "the popups fade away")

	# Camera tilt: a few degrees, and the stick still moves you straight up the screen.
	var tilt := absf(rad_to_deg(camera.rotation))
	check(tilt >= 1.0 and tilt <= 5.0, "the view is tilted a little (%.1f°)" % tilt)
	check(is_equal_approx(player.view_rotation, camera.rotation), "the player reads the sticks through the tilt")
	var on_screen: Vector2 = level.get_viewport().get_canvas_transform().basis_xform(Vector2.UP.rotated(player.view_rotation))
	check(on_screen.normalized().dot(Vector2.UP) > 0.999, "pushing up moves you straight up the screen")

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

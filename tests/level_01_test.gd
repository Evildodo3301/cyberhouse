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
	var t := func(x: int, y: int) -> Vector2: return (Vector2(x, y) + Vector2(0.5, 0.5)) * 8.0   # tile centre
	check(map.tile_px == 8, "thin walls: 8 px tiles")
	check(map.room_count() == 11, "a house of 11 rooms (%d)" % map.room_count())
	var dogs := enemies.filter(func(e): return e.is_dog)
	var people := enemies.filter(func(e): return not e.is_dog)
	check(enemies.size() == 10 and dogs.size() == 2, "an easy first level: 8 enemies and 2 dobermans (%d, %d dogs)" % [enemies.size(), dogs.size()])
	var doors := root.get_tree().get_nodes_in_group("doors")
	check(doors.size() == 11 and doors.all(func(d): return d.length == 32.0), "11 small doors (32 px)")
	var pickups := root.get_tree().get_nodes_in_group("pickups")
	check(pickups.filter(func(p): return p.weapon.id == &"pistol").size() == 2, "2 pistols placed")
	check(pickups.filter(func(p): return p.weapon.id == &"machete").size() == 2, "2 machetes placed")
	check(player.weapon.id == &"fists", "you start unarmed")
	var start_room: int = map.room_at(player.global_position)
	check(start_room >= 0 and enemies.all(func(e): return map.room_at(e.global_position) != start_room), "the start room (the hall by the front door) is safe")
	var exit_zone = root.get_tree().get_first_node_in_group("exit")
	check(exit_zone != null and not exit_zone.open, "exit exists and is locked")

	# Every enemy can walk to you (paths through doors and doorways, round furniture).
	var nav_map: RID = player.get_world_2d().navigation_map
	await wait_frames(2)
	var stuck := enemies.filter(func(e):
		var path := NavigationServer2D.map_get_path(nav_map, e.global_position, player.global_position, true)
		return path.size() == 0 or path[path.size() - 1].distance_to(player.global_position) >= 12.0).map(func(e): return e.name)
	check(stuck.is_empty(), "every enemy has a path to the start %s" % [stuck])

	# Looks: the player wears the pink sheet, every enemy the cop sheet.
	check(player._sprite != null and player._sprite.texture.resource_path.ends_with("player_torso.png"), "the player wears the pink template torso")
	check(player._legs_sprite != null and player._legs_sprite.get_parent().name == "Legs", "the template's feet are on the legs (they turn apart)")
	var pieces := map.get_children().filter(func(c): return c is Sprite2D and (c.region_enabled or c.is_in_group("fancy_furniture")))
	check(pieces.size() >= 80, "lots of furniture (%d pieces)" % pieces.size())
	var fancy_rooms := {}
	for piece in root.get_tree().get_nodes_in_group("fancy_furniture"):
		fancy_rooms[map.room_at(piece.position + piece.offset + piece.texture.get_size() * 0.5)] = true
	check(fancy_rooms.size() == map.room_count(), "fancy furniture in every room (%d of %d)" % [fancy_rooms.size(), map.room_count()])
	var leopard = map.get_children().filter(func(c): return c is Sprite2D and c.name == "LeopardRug")
	check(leopard.size() == 1 and leopard[0].z_index == -1, "the leopard rug lies under the blood")
	check(people.all(func(e): return e.sheet.resource_path.ends_with("cop_suit.png")), "every enemy wears a black suit")
	check(dogs.all(func(e): return e.sheet == null and e.carried_weapon == null and e.active_counters.is_empty()), "dogs: placeholder body, no weapon, no learned counters")
	var thugs := enemies.filter(func(e): return e.carried_weapon and e.carried_weapon.id == &"machete")
	check(thugs.size() == 3, "3 enemies carry a machete")
	check(enemies.filter(func(e): return e.has_gun()).size() == 2, "only 2 enemies have guns")
	check(people.all(func(e): return not e.settings.notice_whole_room and e.settings.reaction_time >= 0.35), "enemies only see what's in front of them, and react a bit slower")
	# Patrols: dogs and most enemies walk a round inside their own room.
	var patrollers := enemies.filter(func(e): return e.patrol_points.size() >= 2)
	print("      patrols: ", patrollers.map(func(e): return "%s:%d" % [e.name, e.patrol_points.size()]))
	check(dogs.all(func(e): return e.patrol_points.size() >= 2), "dogs patrol")
	check(patrollers.size() >= 6, "most enemies patrol (%d of 10)" % patrollers.size())
	check(patrollers.all(func(e): return e.patrol_points.all(func(p): return map.room_at(p) == e._home_room)), "every patrol stays in its room")
	check(enemies.filter(func(e): return e.carried_weapon and e.carried_weapon.id == &"machine_gun").size() == 1, "one enemy has a machine gun")
	check(pickups.filter(func(p): return p.weapon.id == &"machine_gun").size() == 1, "a machine gun lies in the house")
	# Gang carpets: a rug in each big room, a mat at every door, all three designs used.
	var rugs := root.get_tree().get_nodes_in_group("rugs")
	var big_rugs := rugs.filter(func(r): return r.texture.resource_path.get_file().begins_with("rug-"))
	var mats := rugs.filter(func(r): return r.texture.resource_path.get_file().begins_with("doormat-"))
	print("      rugs: ", big_rugs.map(func(r): return r.texture.resource_path.get_file().substr(4, 1)), " mats: ", mats.map(func(r): return r.texture.resource_path.get_file().substr(8, 1)))
	check(big_rugs.size() >= 5, "big rooms have a gang rug in the middle (%d)" % big_rugs.size())
	check(mats.size() == doors.size(), "a doormat at every door")
	var designs := {}
	for r in rugs:
		designs[r.texture.resource_path.get_file().split("-")[1]] = true
	check(designs.size() == 3, "all three gang designs show up")
	check(rugs.all(func(r): return r.z_index == -1), "carpets lie under the blood and furniture")
	check(big_rugs.all(func(r): return map.room_at(r.global_position) >= 0 and map.room_at(r.global_position - r.texture.get_size() * 0.45) == map.room_at(r.global_position + r.texture.get_size() * 0.45)), "each rug lies inside one room")
	var rug_layout := rugs.map(func(r): return [r.texture.resource_path, r.global_position])
	# Furniture never blocks a spawn, a pickup or a door's swing.
	var solids := map.get_children().filter(func(c): return c is StaticBody2D and c.is_in_group("nav_walls") and map.tile(Vector2i(c.position / map.tile_px)) != "#")
	var spots: Array = enemies.map(func(e): return e.global_position) + pickups.map(func(p): return p.global_position)
	var blocked := spots.filter(func(at):
		var q := PhysicsPointQueryParameters2D.new()
		q.position = at
		q.collision_mask = 1
		return not player.get_world_2d().direct_space_state.intersect_point(q).is_empty())
	check(blocked.is_empty(), "no spawn or weapon sits inside furniture %s" % [blocked])
	var in_swing := solids.filter(func(b): return doors.any(func(d): return (b.global_position - (d.global_position + Vector2.RIGHT.rotated(d.rotation) * d.length * 0.5)).length() < d.length * 0.75))
	check(in_swing.is_empty(), "no furniture in a door's swing %s" % [in_swing.map(func(b): return Vector2i(b.position / 8.0))])

	var roamers := enemies.filter(func(e): return not e.stays_in_room)
	print("      roamers: ", roamers.map(func(e): return e.name))
	check(roamers.size() >= 1 and roamers.size() <= 3, "only a few enemies may leave their room (%d of 10)" % roamers.size())

	# Sneaking: an enemy with its back to you doesn't notice you; step in front and it does.
	var living: int = map.room_at(t.call(30, 40))
	var sentry = enemies.filter(func(e): return map.room_at(e.global_position) == living)[0]
	sentry.patrol_points = [] as Array[Vector2]
	sentry._home = t.call(36, 40)
	sentry._home_facing = Vector2.RIGHT
	sentry.global_position = sentry._home
	sentry.facing = Vector2.RIGHT
	sentry._enter(0)
	player.global_position = t.call(32, 40)   # 32 px behind it
	await wait_frames(20)
	check(sentry.state == 0, "you can stand right behind an enemy that hasn't seen you")
	player.global_position = t.call(30, 40)
	await wait_frames(1)
	player.request_attack(Vector2.RIGHT)
	for i in 6:
		player.global_position = player.global_position.move_toward(sentry.global_position - Vector2(16, 0), 4.0)
		await physics_frame
	player.request_attack(Vector2.RIGHT)
	await wait_frames(20)
	check(not sentry.is_alive(), "sneak up behind it and take it out before it turns")
	var watcher = enemies.filter(func(e): return e.is_alive() and map.room_at(e.global_position) == map.room_at(t.call(36, 6)))[0]
	watcher.patrol_points = [] as Array[Vector2]
	watcher._home = watcher.global_position
	watcher._home_facing = Vector2.LEFT
	watcher.facing = Vector2.LEFT
	watcher._enter(0)
	player.global_position = watcher.global_position + Vector2(-48, 0)   # in front, in its cone
	await wait_frames(3)
	check(watcher.state in [1, 2], "step in front of an enemy and it notices you")
	player.global_position = t.call(6, 58)
	await wait_frames(30)

	# Doors: opening one only alerts an enemy that is looking at it.
	var hall_door = doors.filter(func(d): return map.room_at(d.center() + Vector2(24, 0)) == living and absf(d.center().y - t.call(0, 58).y) < 24.0)
	check(hall_door.size() == 1, "found the hall door")
	var guard = load("res://scenes/enemies/grunt.tscn").instantiate()
	guard.settings = load("res://data/easy_grunt_settings.tres")
	guard.position = t.call(26, 58)
	guard.start_facing_degrees = 0.0   # back to the door
	level.get_node("LevelMap").add_child(guard)
	await wait_frames(2)
	player.global_position = t.call(13, 57)
	await wait_frames(4)
	check(guard.state == 0, "a door opening behind an enemy's back goes unnoticed")
	player.global_position = t.call(6, 58)
	await wait_frames(60)
	guard._home_facing = Vector2.LEFT
	guard.facing = Vector2.LEFT
	player.global_position = t.call(13, 57)
	await wait_frames(4)
	check(guard.state in [1, 2], "an enemy watching the door reacts when it opens")
	guard.take_hit(player, Vector2.RIGHT, "melee")
	player.global_position = t.call(6, 58)
	await wait_frames(30)
	var far_room := enemies.filter(func(e): return e.is_alive() and map.room_at(e.global_position) == map.room_at(t.call(90, 10)))
	check(far_room.size() > 0 and far_room.all(func(e): return e.state == 0), "rooms away from you stay calm")

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
	var thug = thugs[0]
	thug.take_hit(player, Vector2.RIGHT, "melee")
	await wait_frames(30)
	var thug_drop := root.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.weapon.id == &"machete" and p.global_position.distance_to(thug.global_position) < 60.0)
	check(thug_drop.size() == 1, "a machete enemy drops a machete on the floor")
	player.equip(load("res://data/weapons/fists.tres"), -1)
	for e in enemies:
		e.set_physics_process(true)

	# Shoot: a tiny triple kick, and the void flashes neon then fades.
	player.global_position = t.call(6, 58)
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

	# The shot was heard everywhere: for 3 s, no stay-in-room enemy leaves its room.
	var left_room := []
	for i in 180:
		await physics_frame
		for e in enemies:
			if e.stays_in_room and e.is_alive() and map.room_at(e.global_position) != e._home_room and not left_room.has(e.name):
				left_room.append(e.name)
	check(left_room.is_empty(), "stay-in-room enemies stop at their doorway %s" % [left_room])
	var holding := []
	for door in root.get_tree().get_nodes_in_group("doors"):
		for body in door._push_zone.get_overlapping_bodies():
			if body.is_in_group("enemies") and body.stays_in_room:
				holding.append(body.name)
	check(holding.is_empty(), "waiting enemies never hold a door open %s" % [holding])

	# Kill everyone: the exit opens; walk in: LEVEL COMPLETE. (Restart first:
	# a roamer may have got you during the waiting check.)
	if true:
		# A retry keeps the carpets where they were.
		root.get_node("Game").restart_room()
		await process_frame
		await process_frame
		await wait_frames(3)
		level = current_scene
		player = level.get_node("Player")
		exit_zone = root.get_tree().get_first_node_in_group("exit")
		var again := root.get_tree().get_nodes_in_group("rugs").map(func(r): return [r.texture.resource_path, r.global_position])
		check(again == rug_layout, "a retry keeps the same carpets in the same places")
	player.global_position = t.call(6, 58)
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

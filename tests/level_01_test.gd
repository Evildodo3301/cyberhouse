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

	# Looks: the player wears the pink sheet, every enemy the cop sheet.
	check(player._sprite != null and player._sprite.texture.resource_path.ends_with("player_torso.png"), "the player wears the pink template torso")
	check(player._legs_sprite != null and player._legs_sprite.get_parent().name == "Legs", "the template's feet are on the legs (they turn apart)")
	var pieces := map.get_children().filter(func(c): return c is Sprite2D and c.region_enabled)
	check(pieces.size() == 22, "22 pieces of furniture placed (%d)" % pieces.size())
	check(enemies.all(func(e): return e.sheet.resource_path.ends_with("cop.png")), "every enemy looks like a cop")
	var roamers := enemies.filter(func(e): return not e.stays_in_room).size()
	print("      roamers: ", enemies.filter(func(e): return not e.stays_in_room).map(func(e): return e.name))
	check(roamers >= 1 and roamers <= 3, "only a few enemies may leave their room (%d of 9)" % roamers)

	# Push the start room's door open: the two cops behind it react at once.
	var door_spot := Vector2(15 * 16 - 10, 17 * 16 + 8)
	var behind_door := enemies.filter(func(e): return map.room_at(e.global_position) == map.room_at(Vector2(20 * 16, 17 * 16)))
	check(behind_door.size() == 2 and behind_door.all(func(e): return e.state == 0), "the cops behind the door start calm")
	player.global_position = door_spot
	await wait_frames(4)
	check(behind_door.all(func(e): return e.state in [1, 2]), "opening the door alerts the room behind it")
	var far_room := enemies.filter(func(e): return map.room_at(e.global_position) == map.room_at(Vector2(40 * 16, 3 * 16)))
	check(far_room.all(func(e): return e.state == 0), "rooms away from the door stay calm")

	# Shoot: a tiny triple kick, and the void flashes neon then fades.
	player.global_position = Vector2(3 * 16 + 8, 20 * 16 + 8)
	player.equip(load("res://data/weapons/pistol.tres"), 8)
	var camera = level.get_node("GameCamera")
	var void_flash = level.get_node("VoidFlash")
	player.request_attack(Vector2.LEFT)
	await wait_frames(1)
	check(camera._kicks.size() >= 2, "a shot kicks the camera in quick steps")
	var biggest := 0.0
	for k in camera._kicks:
		biggest = maxf(biggest, k.length())
	check(biggest > 0.0 and biggest <= 1.0, "the kick is tiny (%.2f px)" % biggest)
	await process_frame
	check(void_flash.strength > 0.0 and RenderingServer.get_default_clear_color() != void_flash._base, "the void flashes on a shot")
	await create_timer(1.0).timeout
	check(camera._kicks.is_empty(), "the kick is over quickly")
	check(void_flash.strength == 0.0, "the void flash fades out")

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

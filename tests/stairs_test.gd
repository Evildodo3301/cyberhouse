extends SceneTree
## Checks the stairs between the two floors of level 1: each floor is its
## own scene. Clear floor 1, step on the stairs and you walk up on your own,
## the screen fades, a loading screen shows, and you arrive on floor 2 with
## your score. Dying on floor 2 restarts floor 2 only.
##   godot --headless --script res://tests/stairs_test.gd

var failures := 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


func wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func kill_everyone() -> void:
	for enemy in root.get_tree().get_nodes_in_group("enemies"):
		if enemy.is_alive():
			enemy.take_hit(current_scene.get_node("Player"), Vector2.RIGHT, "fists")
			enemy.take_hit(current_scene.get_node("Player"), Vector2.RIGHT, "fists")


func _initialize() -> void:
	var game := root.get_node("Game")
	var t := func(x: int, y: int) -> Vector2: return (Vector2(x, y) + Vector2(0.5, 0.5)) * 8.0
	root.get_node("TacticTracker").clear_room(&"level_01")
	change_scene_to_file("res://scenes/levels/level_01.tscn")
	await process_frame
	await process_frame
	await wait_frames(3)
	var player = current_scene.get_node("Player")
	var exit_zone = root.get_tree().get_first_node_in_group("exit")
	player.global_position = t.call(17, 42)
	await wait_frames(5)
	check(current_scene.name == "Level01", "the stairs stay shut while anyone on floor 1 is alive")
	player.global_position = t.call(45, 48)
	kill_everyone()
	await wait_frames(5)
	var alive: Array = root.get_tree().get_nodes_in_group("enemies").filter(func(e): return e.is_alive())
	check(alive.is_empty() and exit_zone.open, "floor 1 cleared: the stairs open")
	var score: int = current_scene.get_node("ScoreBoard").score
	check(score > 0, "kills scored (%d)" % score)

	player.equip(load("res://data/weapons/machete.tres"), -1)
	player.global_position = t.call(20, 42)
	await wait_frames(3)
	check(player.auto_walk == Vector2.LEFT, "on the stairs you walk up them on your own")
	var start: Vector2 = player.global_position
	player.request_attack(Vector2.RIGHT)
	await wait_seconds(0.4)
	check(player.global_position.x < start.x - 10.0, "and keep walking (%.0f px)" % (start.x - player.global_position.x))
	var fade = current_scene.find_child("FadeToBlack", true, false)
	check(fade != null and fade.color.a > 0.2, "while the screen fades to black")
	await wait_seconds(0.7)
	var loading = game.get_node_or_null("LoadingScreen")
	check(loading != null, "then the loading screen comes up")
	var shown = loading.find_child("Picture", true, false) if loading else null
	check(shown != null and shown.texture.resource_path == "res://assets/story/stairs_up.jpg", "showing Fianso's picture of the hero going up the stairs")
	await wait_seconds(2.2)
	await wait_frames(3)
	check(current_scene.name == "Level01Floor2", "and you arrive on floor 2, its own map")
	check(game.get_node_or_null("LoadingScreen") == null, "the loading screen fades away")
	player = current_scene.get_node("Player")
	check(player.global_position == t.call(25, 41) and player.auto_walk == Vector2.ZERO, "at the top of the stairs, back in control")
	check(current_scene.get_node("ScoreBoard").score == score, "with the score you had on floor 1")
	check(player.weapon.id == &"machete", "and the weapon you were holding")

	# Floor 2 itself (the Level Designer's draft, stand-in blocks for furniture).
	var map = current_scene.get_node("LevelMap")
	var enemies: Array = root.get_tree().get_nodes_in_group("enemies")
	check(enemies.size() == 5 and enemies.filter(func(e): return e.is_dog).size() == 1, "floor 2 has 4 people and a doberman (%d)" % enemies.size())
	check(map.picture == null, "no picture yet: floor 2's art waits for Fianso's yes")
	var space: PhysicsDirectSpaceState2D = player.get_world_2d().direct_space_state
	var q := PhysicsPointQueryParameters2D.new()
	q.position = t.call(18, 23)   # a bit of furniture (x) in the bedroom
	q.collision_mask = 1
	check(map.tile(Vector2i(18, 23)) == "x" and not space.intersect_point(q).is_empty(), "furniture stand-ins block")
	var nav_map: RID = player.get_world_2d().navigation_map
	await wait_frames(2)
	var stuck := enemies.filter(func(e):
		var path := NavigationServer2D.map_get_path(nav_map, e.global_position, player.global_position, true)
		return path.size() == 0 or path[path.size() - 1].distance_to(player.global_position) >= 12.0).map(func(e): return e.name)
	check(stuck.is_empty(), "every enemy on floor 2 has a path to you %s" % [stuck])
	var circle := CircleShape2D.new()
	circle.radius = 7.0
	var squeezed := enemies.filter(func(e):
		var sq := PhysicsShapeQueryParameters2D.new()
		sq.shape = circle
		sq.transform = Transform2D(0.0, e.global_position)
		sq.collision_mask = 1 | 32
		return not space.intersect_shape(sq).is_empty()).map(func(e): return e.name)
	check(squeezed.is_empty(), "every enemy body fits where it starts on floor 2 %s" % [squeezed])
	var floor2_exit = root.get_tree().get_first_node_in_group("exit")
	check(floor2_exit.walk == Vector2.LEFT and not floor2_exit.open, "floor 2's exit is back down the stairs, shut for now")

	# Dying on floor 2 restarts floor 2, with the score you arrived with.
	game.restart_room()
	await process_frame
	await process_frame
	await wait_frames(3)
	check(current_scene.name == "Level01Floor2" and current_scene.get_node("ScoreBoard").score == score, "dying restarts floor 2 only, score as you arrived")

	kill_everyone()
	await wait_frames(5)
	player = current_scene.get_node("Player")
	var total: int = current_scene.get_node("ScoreBoard").score
	player.global_position = t.call(20, 42)
	await wait_seconds(1.3)
	var death_screen = current_scene.get_node("DeathScreen")
	check(death_screen.visible and death_screen.next_scene == "res://scenes/levels/level_02.tscn", "down the stairs: level complete")
	check(total > score and str(total) in death_screen._label.text, "the score adds up both floors (%d)" % total)
	game.load_level("res://scenes/levels/level_02.tscn")
	check(game.carried.is_empty(), "a new level starts from zero")

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

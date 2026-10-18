extends SceneTree
## Automated check of M1 without a phone. Run from the project folder with:
##   godot --headless --script res://tests/m1_smoke_test.gd
## It fakes touch input and checks the player moves, aims and kills.

var failures := 0


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	root.push_input(e, true)   # true = positions are in game pixels


func drag(index: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	root.push_input(e, true)   # true = positions are in game pixels


## M1 checks run without enemies, so nothing else moves or kills.
func remove_enemies() -> void:
	for enemy in root.get_tree().get_nodes_in_group("enemies"):
		enemy.free()


func reload_room(keep_enemies: bool) -> void:
	root.get_node("Game").restart_room()
	await wait_frames(5)
	if not keep_enemies:
		remove_enemies()
	await wait_frames(1)


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
	remove_enemies()
	var main := current_scene
	var player = main.get_node("Player")
	var dummy = main.get_node("Dummy1")
	var screen := root.get_visible_rect().size

	# 1. Left thumb drags to the right: player should move right.
	var start: Vector2 = player.global_position
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))
	await wait_frames(30)
	check(player.global_position.x > start.x + 20, "left stick moves the player")
	check(absf(player.velocity.length() - player.settings.move_speed) < 1.0, "reaches full speed")
	touch(0, Vector2(140, 250), false)
	await wait_frames(6)
	check(player.velocity.length() < 1.0, "stops quickly after lifting the thumb")

	# 2. Put the dummy just up-right of the player, aim roughly at it, release.
	player.global_position = Vector2(200, 200)
	dummy.global_position = Vector2(215, 185)
	await wait_frames(2)
	var right := Vector2(screen.x * 0.75, 250)
	touch(1, right, true)
	drag(1, right + Vector2(30, -25))   # aim is a few degrees off the dummy
	await wait_frames(3)
	touch(1, right + Vector2(30, -25), false)
	await wait_frames(30)
	check(not dummy.is_alive(), "aim + release kills the dummy (with aim assist)")
	check(root.get_node("TacticTracker").get_room_reports().size() == 1, "kill was reported to TacticTracker")
	check(main.get_node("Gore").kill_count == 1, "body and blood painted on the floor")

	# 3. Quick tap attacks the nearest target in front.
	var dummy2 = main.get_node("Dummy2")
	player.global_position = Vector2(60, 40)
	player.facing = Vector2.RIGHT
	dummy2.global_position = Vector2(78, 48)
	await wait_frames(25)   # let recovery from the last swing finish
	touch(2, right, true)
	await wait_frames(2)
	touch(2, right, false)
	await wait_frames(20)
	check(not dummy2.is_alive(), "quick tap hits the nearest target in front")

	# 4. Releasing far from any target swings but hits nothing.
	var dummy3 = main.get_node("Dummy3")
	player.global_position = Vector2(400, 280)
	await wait_frames(25)
	touch(3, right, true)
	drag(3, right + Vector2(-30, 0))
	await wait_frames(3)
	touch(3, right + Vector2(-30, 0), false)
	await wait_frames(20)
	check(dummy3.is_alive(), "a miss does not kill far-away targets")

	# 5. Walls stop the player.
	player.global_position = Vector2(20, 160)
	touch(4, Vector2(100, 250), true)
	drag(4, Vector2(60, 250))
	await wait_frames(60)
	touch(4, Vector2(60, 250), false)
	check(player.global_position.x >= 6.0, "left wall blocks the player")

	# 6. Restart keeps the tracker's memory (it lives in an autoload).
	await reload_room(false)
	check(root.get_node("TacticTracker").get_room_reports().size() == 2, "kill memory survives a room restart")
	check(current_scene.get_node("Gore").kill_count == 0, "restart gives a clean floor")

	# 7. Tap the bomb button: the bomb flies ~5 widths and kills what's there.
	main = current_scene
	player = main.get_node("Player")
	dummy3 = main.get_node("Dummy3")
	var bomb_button = main.get_node("TouchControls/BombButton")
	player.global_position = Vector2(150, 290)
	player.facing = Vector2.RIGHT
	dummy3.global_position = Vector2(222, 295)
	await wait_frames(2)
	var button_pos: Vector2 = bomb_button.get_button_center()
	touch(5, button_pos, true)
	await wait_frames(2)
	touch(5, button_pos, false)
	await wait_frames(3)
	check(player.bombs_left == 0 and bomb_button.bombs_left == 0, "bomb used, button shows 0")
	check(dummy3.is_alive(), "nothing dies before the fuse runs out")
	await wait_frames(90)
	check(not dummy3.is_alive(), "bomb blast kills the target")
	check(player.is_alive(), "thrower outside the blast survives")
	await wait_frames(30)   # let the explosion finish
	touch(5, button_pos, true)
	await wait_frames(2)
	touch(5, button_pos, false)
	await wait_frames(3)
	check(main.get_children().filter(func(n): return n.has_method("throw")).is_empty(), "no bomb without bombs left")

	# 8. A bomb thrown into a nearby wall kills the player too.
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	player.global_position = Vector2(20, 160)
	player.facing = Vector2.LEFT
	await wait_frames(2)
	player.request_bomb(Vector2.ZERO)
	await wait_frames(100)
	check(not player.is_alive(), "own bomb kills the player")
	check(main.get_node("DeathScreen").visible, "TAP TO RETRY is shown")
	await wait_frames(20)
	touch(6, Vector2(300, 200), true)
	await wait_frames(5)
	check(current_scene.get_node("Player").is_alive(), "a tap restarts the room")
	check(current_scene.get_node("Player").bombs_left == 1, "restart refills the bomb")

	# ---------------------------------------------------------- doors
	# 9. Walking into the door swings it open, and you get through.
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	var door = main.get_node("SwingDoor")
	player.global_position = Vector2(270, 140)
	await wait_frames(2)
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))
	await wait_frames(15)
	check(absf(door.angle) > 30.0, "walking into the door pushes it open")
	await wait_frames(45)
	touch(0, Vector2(140, 250), false)
	check(player.global_position.x > 312.0, "player walks through the doorway")
	await wait_frames(90)
	check(is_zero_approx(door.angle), "door swings shut by itself")

	# 10. A door slammed open knocks down whoever is behind it.
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	dummy2 = main.get_node("Dummy2")
	dummy2.global_position = Vector2(320, 150)
	player.global_position = Vector2(284, 140)
	await wait_frames(2)
	var knocked := false
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))
	for i in 30:
		await wait_frames(1)
		if dummy2._knocked:
			knocked = true
	touch(0, Vector2(140, 250), false)
	check(knocked, "door slam knocks the dummy down")

	# --------------------------------------------------------- M2 grunt
	# 11. The guard sees you, pauses (reaction time), then chases and kills.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	var guard = main.get_node("GruntGuard")
	player.global_position = Vector2(380, 250)
	await wait_frames(3)
	check(guard.state == 1, "grunt spots you and shows '!' (alert)")
	await wait_frames(4)
	check(guard.state == 1, "it waits out its reaction time before moving")
	await wait_frames(12)
	check(guard.state == 2 or guard.state == 3, "then it charges")
	await wait_frames(60)
	check(not player.is_alive(), "its swing kills the player")
	var events: Array = root.get_node("TacticTracker").events_by_room.get(&"m1_test_arena", [])
	var tracker = root.get_node("TacticTracker")
	var deaths: Array = tracker.get_attempt_reports(tracker.current_attempt()).filter(
		func(e): return e.get("type") == "player_death")
	check(deaths.size() == 1 and deaths[0].killer_type == "enemy_melee", "player death is logged for M3, per attempt")
	var bomb_deaths: Array = events.filter(func(e): return e.get("killer_type") == "own_bomb")
	check(bomb_deaths.size() == 1 and bomb_deaths[0].attempt < tracker.current_attempt(), "earlier own-bomb death sits in an earlier attempt")

	# 12. Strike first from behind: one hit kills the grunt.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	guard = main.get_node("GruntGuard")
	player.global_position = guard.global_position + Vector2(15, 2)
	await wait_frames(1)
	player.request_attack(player.global_position.direction_to(guard.global_position))
	await wait_frames(10)
	check(not guard.is_alive(), "your swing kills the grunt before it reacts")
	check(main.get_node("Gore").kill_count == 1, "the grunt's body stays on the floor")
	check(player.is_alive(), "and you survive")

	# 13. A bomb's noise sends the patrolling grunt to search; it paths
	# through the doorway, pushing the door open.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntGuard").free()
	var patrol = main.get_node("GruntPatrol")
	player.global_position = Vector2(60, 300)
	player.facing = Vector2.UP
	player.request_bomb(Vector2.ZERO)
	await wait_frames(90)
	check(patrol.state == 4 or patrol.state == 2, "bomb blast is heard: grunt goes to investigate")
	var crossed := false
	for i in 300:
		await wait_frames(1)
		if patrol.global_position.x < 290.0:
			crossed = true
			break
	check(crossed, "grunt finds a path through the door into your room")

	# 14. Split body: left stick walks right while the right stick aims up.
	# Torso faces the aim, legs face the walk.
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	player.global_position = Vector2(200, 200)
	await wait_frames(2)
	var aim_at := Vector2(screen.x * 0.75, 250)
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))
	touch(1, aim_at, true)
	drag(1, aim_at + Vector2(0, -40))
	await wait_frames(20)
	check(Vector2.from_angle(player.get_node("Torso").rotation).dot(Vector2.UP) > 0.9, "torso turns to the right stick while walking")
	check(Vector2.from_angle(player.get_node("Legs").rotation).dot(Vector2.RIGHT) > 0.95, "legs face the way you walk, not the aim")
	touch(1, aim_at + Vector2(0, -40), false)   # lifting the thumb also swings
	await wait_frames(15)
	check(Vector2.from_angle(player.get_node("Torso").rotation).dot(Vector2.RIGHT) > 0.9, "no aim: torso follows the walk again")
	touch(0, Vector2(140, 250), false)
	await wait_frames(10)
	check(Vector2.from_angle(player.get_node("Legs").rotation).dot(Vector2.RIGHT) > 0.95, "standing still: legs stay put")

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

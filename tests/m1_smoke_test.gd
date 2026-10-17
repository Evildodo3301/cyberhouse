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


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	change_scene_to_file("res://scenes/main.tscn")
	await process_frame
	await process_frame
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
	player.global_position = Vector2(300, 120)
	player.facing = Vector2.RIGHT
	dummy2.global_position = Vector2(318, 128)
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
	root.get_node("Game").restart_room()
	await wait_frames(5)
	check(root.get_node("TacticTracker").get_room_reports().size() == 2, "kill memory survives a room restart")
	check(current_scene.get_node("Gore").kill_count == 0, "restart gives a clean floor")

	# 7. Tap the bomb button: the bomb flies ~5 widths and kills what's there.
	main = current_scene
	player = main.get_node("Player")
	dummy3 = main.get_node("Dummy3")
	var bomb_button = main.get_node("TouchControls/BombButton")
	player.global_position = Vector2(300, 250)
	player.facing = Vector2.RIGHT
	dummy3.global_position = Vector2(372, 255)
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
	root.get_node("Game").restart_room()
	await wait_frames(5)
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

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

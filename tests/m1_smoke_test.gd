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
	var open_sign := signf(door.angle)
	var wobbled := false
	for i in 180:
		await physics_frame
		if signf(door.angle) == -open_sign and absf(door.angle) > 5.0:
			wobbled = true
	check(is_zero_approx(door.angle), "door swings shut by itself")
	check(wobbled, "it wobbles past closed before it settles")

	# 9b. A bullet that hits the door knocks it a little way open, then it shuts.
	player.global_position = Vector2(360, 140)
	player.equip(load("res://data/weapons/pistol.tres"), 8)
	await wait_frames(2)
	var bullet: Bullet = preload("res://scenes/weapons/bullet.tscn").instantiate()
	main.add_child(bullet)
	bullet.fire(player.global_position, door.center() - player.global_position, player.weapon, player)
	var widest := 0.0
	for i in 30:
		await physics_frame
		widest = maxf(widest, absf(door.angle))
	check(widest > 10.0 and widest < 40.0, "a shot nudges the door open a little (%.0f degrees)" % widest)
	await wait_frames(150)
	check(is_zero_approx(door.angle), "the nudged door shuts again")

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

	# --------------------------------------------- crosshair, guns, rooms
	# 15. Fists at the start; the crosshair sits at punch reach and turns red
	# when the punch would land.
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	check(player.weapon.id == &"fists" and player.ammo == -1, "every level starts with bare fists")
	player.global_position = Vector2(200, 230)
	player.facing = Vector2.RIGHT
	await wait_frames(2)
	var crosshair: Sprite2D = player._crosshair
	check(absf(crosshair.global_position.distance_to(player.global_position) - player.weapon.reach) < 1.0, "crosshair sits at the end of the punch reach")
	check(not player.crosshair_on_target, "crosshair is white with nobody in reach")
	dummy = main.get_node("Dummy1")
	dummy.global_position = player.global_position + Vector2(18, 0)
	await wait_frames(2)
	check(player.crosshair_on_target and crosshair.modulate.r > 0.9 and crosshair.modulate.g < 0.3, "crosshair turns red over a target")

	# 16. Walk over the pistol on the floor: picked up with a full magazine.
	var pickup = main.get_node("PistolPickup")
	player.global_position = pickup.global_position + Vector2(30, 0)
	dummy.global_position = Vector2(200, 60)
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(60, 250))
	await wait_frames(30)
	touch(0, Vector2(60, 250), false)
	check(player.weapon.id == &"pistol" and player.ammo == 8, "walking over a gun picks it up")
	check(not is_instance_valid(pickup), "the gun is gone from the floor")

	# 17. Shoot a target far beyond punch reach.
	dummy = main.get_node("Dummy2")
	player.global_position = Vector2(60, 170)
	dummy.global_position = Vector2(120, 170)
	await wait_frames(3)
	player.facing = Vector2.RIGHT
	await wait_frames(1)
	check(player.crosshair_on_target, "armed: crosshair reaches the far target and is red")
	player.request_attack(Vector2.RIGHT)
	await wait_frames(3)
	var flying: Array = main.get_children().filter(func(n): return n is Bullet)
	check(flying.size() == 1 and dummy.is_alive(), "the shot is a bullet you can see flying")
	await wait_frames(12)
	check(not dummy.is_alive(), "a pistol shot kills at range")
	check(player.ammo == 7, "the shot used one bullet")
	# Range: half a screen, not the whole room.
	var far_dummy = main.get_node("Dummy1")
	far_dummy.global_position = Vector2(60 + 140, 230)
	player.global_position = Vector2(60, 230)
	await wait_frames(16)
	player.request_attack(Vector2.RIGHT)
	await wait_frames(30)
	check(far_dummy.is_alive(), "bullets drop after the pistol's range")
		# Walls stop bullets.
	dummy = main.get_node("Dummy3")
	dummy.global_position = Vector2(160, 96)   # behind the pillar at x 120-152
	player.global_position = Vector2(90, 96)
	await wait_frames(20)
	player.request_attack(Vector2.RIGHT)
	await wait_frames(15)
	check(dummy.is_alive(), "walls stop bullets")
	await wait_frames(16)   # let the gun recover

	# 18. Empty the gun: it drops to the floor and you are back to fists.
	for i in 6:
		player.request_attack(Vector2.UP)
		await wait_frames(16)
	check(player.weapon.id == &"fists", "an empty gun is dropped: back to fists")
	await wait_frames(30)
	var empties: Array = root.get_tree().get_nodes_in_group("pickups").filter(func(p): return not p.is_usable())
	check(empties.size() == 1, "the empty gun lies on the floor and can't be picked up")

	# 19. Enemies notice you the moment you enter their room, from behind,
	# but still show '!' for the reaction time first.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")   # faces left (200 degrees)
	player.global_position = Vector2(470, 300)   # behind it, out of its cone
	await wait_frames(3)
	check(guard.state == 1, "entering its room: noticed at once, even from behind")
	player.global_position = Vector2(200, 300)

	# 20. A killed enemy drops his gun, flung away from the hit.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	player.global_position = guard.global_position + Vector2(-15, 0)
	await wait_frames(1)
	player.request_attack(Vector2.RIGHT)
	await wait_frames(30)
	var drops: Array = root.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.name != "PistolPickup")
	check(not guard.is_alive() and drops.size() == 1, "a killed grunt drops his gun")
	check(drops.size() == 1 and drops[0].global_position.x > guard.global_position.x + 8.0, "the gun is flung in the direction of the hit")

	# ------------------------------------------------- M3 learning enemies
	tracker = root.get_node("TacticTracker")
	var room := &"m1_test_arena"
	# 21. The rules, fed with fake reports: block the death move + the best move.
	tracker.clear_room(room)
	tracker.start_attempt()
	var rush_kill := {"victim": "G", "weapon": "melee", "distance": 15.0, "player_speed": 90.0, "at_door": false, "enemy_state": "CHASE"}
	tracker.report_kill(rush_kill.duplicate())
	tracker.report_kill(rush_kill.duplicate())
	tracker.report_kill({"victim": "D", "weapon": "melee", "distance": 15.0, "player_speed": 90.0, "at_door": false})
	check(tracker.get_room_reports()[2].tactic == &"", "dummy kills teach the room nothing")
	tracker.report_player_death({"killer_type": "enemy_melee", "in_doorway": true, "player_speed": 0.0, "last_attack": "", "last_attack_seconds_ago": -1.0})
	check(tracker.get_active_counters() == [&"DOOR_AMBUSH", &"RUSH"], "death in a door blocks DOOR AMBUSH plus your best move (RUSH)")
	check(tracker.take_new_blocks() == [&"DOOR_AMBUSH", &"RUSH"] and tracker.take_new_blocks().is_empty(), "both are announced once")
	tracker.start_attempt()
	tracker.report_kill({"victim": "G", "weapon": "pistol", "distance": 90.0, "player_speed": 0.0, "at_door": false, "enemy_state": "CHASE"})
	tracker.report_player_death({"killer_type": "own_bomb", "in_doorway": false, "player_speed": 0.0, "last_attack": "bomb", "last_attack_seconds_ago": 1.2})
	check(tracker.get_active_counters() == [&"BOMB", &"LONG_RANGE"], "never more than 2 blocked of 4: the oldest drop out")
	for i in 3:
		tracker.start_attempt()
		tracker.report_player_death({"killer_type": "enemy_melee", "in_doorway": false, "player_speed": 90.0, "last_attack": "", "last_attack_seconds_ago": -1.0})
	check(tracker.get_active_counters() == [&"LONG_RANGE", &"RUSH"] or tracker.get_active_counters() == [&"BOMB", &"RUSH"], "a rushing death blocks RUSH")
	var before: Array = tracker.get_active_counters()
	tracker.start_attempt()
	tracker.report_player_death({"killer_type": "own_bomb", "in_doorway": true, "player_speed": 0.0, "last_attack": "bomb", "last_attack_seconds_ago": 0.5})
	check(tracker.get_active_counters() == before, "after 5 deaths in a room nothing new is blocked")
	tracker.clear_room(room)
	check(tracker.get_active_counters().is_empty(), "clearing the room forgets everything")

	# 22. A real death on screen: the restart shows PATTERN LOGGED, eyes glow.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	player.global_position = guard.global_position + Vector2(-60, 0)
	player.velocity = Vector2(96, 0)
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))   # run straight at it
	for i in 120:
		await wait_frames(1)
		if not player.is_alive():
			break
	touch(0, Vector2(140, 250), false)
	check(not player.is_alive() and tracker.get_active_counters().has(&"RUSH"), "dying mid-rush blocks RUSH")
	await reload_room(true)
	main = current_scene
	var hud = main.get_node("PatternLogged")
	check(hud._message.visible and "PATTERN LOGGED: RUSH" in hud._message.text, "the restart flashes PATTERN LOGGED: RUSH")
	check("RUSH" in hud._blocked.text, "the blocked move stays listed on screen")
	guard = main.get_node("GruntGuard")
	check(guard.tell_color.a > 0.0 and guard.counters(&"RUSH"), "adapted grunts have glowing eyes")

	# 22b. Running into it without swinging still counts as a rush (the bump
	# stops you dead just before its hit, which used to hide the rush).
	tracker.clear_room(room)
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	player.global_position = guard.global_position + Vector2(-100, 0)
	player.velocity = Vector2(96, 0)
	for i in 150:   # keep steering straight at it, as a thumb would
		var dir: Vector2 = player.global_position.direction_to(guard.global_position).rotated(-player.view_rotation)
		Input.action_release("move_left")
		Input.action_release("move_up")
		Input.action_release("move_down")
		Input.action_press("move_right", maxf(dir.x, 0.0))
		Input.action_press("move_down" if dir.y > 0.0 else "move_up", absf(dir.y))
		await wait_frames(1)
		if not player.is_alive():
			break
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	check(not player.is_alive() and tracker.get_active_counters().has(&"RUSH"), "dying after running into it blocks RUSH")
	await reload_room(true)
	main = current_scene
	guard = main.get_node("GruntGuard")

	# 23. RUSH counter: run at it and it feints (one quick step back), then strikes.
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	player.global_position = guard.global_position + Vector2(-70, 0)
	await wait_frames(20)   # it notices you and starts to come
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))
	var feinted := false
	var struck_back := false
	var backing_frames := 0
	var fastest := 0.0
	for i in 60:
		await wait_frames(1)
		if not player.is_alive():
			break
		fastest = maxf(fastest, guard.velocity.length())
		var away: bool = guard.velocity.dot(guard.global_position - player.global_position) > 0.0
		if guard._bark_text == "FEINT" and away:
			feinted = true
		if away:
			backing_frames += 1
		if feinted and (guard.state == 3 or guard._feint_phase == 2):   # ATTACK, or lunging in
			struck_back = true
	touch(0, Vector2(140, 250), false)
	check(feinted, "rushed grunt feints: a quick step back, calling FEINT")
	check(struck_back, "after the feint it strikes instead of backing off")
	check(backing_frames <= 20, "it never backs off for long (%d frames)" % backing_frames)
	check(fastest <= guard.settings.chase_speed * maxf(guard.settings.feint_lunge_speed, guard.settings.charge_speed) + 0.5, "only the short bursts are faster than its chase")

	# 24. DOOR_AMBUSH counter: wait beside the door and it won't come through.
	tracker.clear_room(room)
	tracker.blocked_by_room[room] = [&"DOOR_AMBUSH"]
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntGuard").free()
	var patrol2 = main.get_node("GruntPatrol")
	player.global_position = Vector2(284, 140)   # just left of the doorway
	root.get_node("Game").make_noise(player.global_position, 1.0)
	var held := false
	var came_through := false
	for i in 240:
		await wait_frames(1)
		if patrol2._bark_text == "HOLD":
			held = true
		if patrol2.global_position.x < 300.0:
			came_through = true
	check(held and not came_through, "door camper: the grunt holds outside the door (HOLD)")

	# 25. LONG_RANGE counter: hold a gun far away and it hides behind a wall.
	tracker.blocked_by_room[room] = [&"LONG_RANGE"]
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	player.equip(load("res://data/weapons/pistol.tres"), -1)
	player.global_position = Vector2(364, 150)   # the pillar at y 200-224 sits between you
	var hid := false
	for i in 120:
		await wait_frames(1)
		var ray := PhysicsRayQueryParameters2D.create(player.global_position, guard.global_position, 1 | 16)
		if guard._bark_text == "COVER" and not player.get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			hid = true
			break
	check(hid, "gun at range: the grunt takes cover out of your line of fire (COVER)")
	var charged := false
	for i in 150:
		await wait_frames(1)
		if guard._bark_text == "GO" and guard.velocity.dot(player.global_position - guard.global_position) > 0.0:
			charged = true
			break
	check(charged, "it hides only for a moment, then charges you")

	# 26. BOMB counter: it runs from a landed bomb and survives it.
	tracker.blocked_by_room[room] = [&"BOMB"]
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	player.global_position = Vector2(370, 270)
	await wait_frames(2)
	player.request_bomb(Vector2.RIGHT)
	await wait_frames(25)
	check(guard._flee_time > 0.0, "a bomb lands near it: it scatters")
	await wait_frames(70)
	check(guard.is_alive(), "and it survives the blast")
	tracker.clear_room(room)

	# 26b. Closing in to attack, a melee enemy bursts toward you, then slows again.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	player.global_position = guard.global_position + Vector2(-110, 0)
	var far_speed := 0.0
	var burst_speed := 0.0
	for i in 90:
		await wait_frames(1)
		if guard.state != 2:
			continue
		var d: float = guard.global_position.distance_to(player.global_position)
		if d > guard.settings.charge_range + 10.0:
			far_speed = maxf(far_speed, guard.velocity.length())
		else:
			burst_speed = maxf(burst_speed, guard.velocity.length())
		if guard.state == 3 or not player.is_alive():
			break
	check(far_speed <= guard.settings.chase_speed + 0.5, "from far away it runs at its normal speed (%.0f)" % far_speed)
	check(burst_speed >= guard.settings.chase_speed * guard.settings.charge_speed - 1.0, "close in, it bursts at you to attack (%.0f)" % burst_speed)

	# 27. Gun enemies shoot back: no warning, just a 0.2 s delay.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	guard.carried_weapon = load("res://data/weapons/pistol.tres")
	player.global_position = guard.global_position + Vector2(-60, 0)
	var aim_frame := -1
	var shot_frame := -1
	for i in 90:
		await wait_frames(1)
		if aim_frame < 0 and guard.state == 7:
			aim_frame = i
		if shot_frame < 0 and guard._struck and guard.state == 7:
			shot_frame = i
		if not player.is_alive():
			break
	check(aim_frame >= 0, "a gun enemy in range stops and aims at you")
	var delay := (shot_frame - aim_frame) / 60.0
	check(shot_frame > aim_frame and delay >= 0.15 and delay <= 0.25, "it fires after about 0.2 s (%.2f s)" % delay)
	check(not player.is_alive(), "its bullet kills you")
	var gun_deaths: Array = tracker.get_attempt_reports(tracker.current_attempt()).filter(
		func(e): return e.get("type") == "player_death" and e.get("killer_type") == "enemy_gun")
	check(gun_deaths.size() == 1, "the death is logged as a gun kill")

	# 28. Off screen it never fires.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	guard.carried_weapon = load("res://data/weapons/pistol.tres")
	# Headless the screen is square (640x640): zoom in so 66 px is past its edge.
	main.get_node("GameCamera").zoom = Vector2(6, 6)
	player.global_position = guard.global_position + Vector2(0, -66)   # in range, past the screen's top edge
	await wait_frames(3)
	var fired := false
	for i in 40:
		await wait_frames(1)
		guard.global_position = player.global_position + Vector2(0, 66)   # hold it there
		if guard._struck and guard.state == 7:
			fired = true
	check(not guard.on_screen() and not fired and player.is_alive(), "an enemy off screen doesn't shoot")

	# 29. Learned counters with a gun enemy: FEINT ends in a shot.
	tracker.clear_room(room)
	tracker.blocked_by_room[room] = [&"RUSH"]
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	guard.carried_weapon = load("res://data/weapons/pistol.tres")
	player.global_position = guard.global_position + Vector2(-70, 0)
	player.velocity = Vector2(96, 0)
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))
	var feint_then_aim := false
	var saw_feint := false
	for i in 60:
		await wait_frames(1)
		if guard._bark_text == "FEINT":
			saw_feint = true
		if saw_feint and guard.state == 7:
			feint_then_aim = true
			break
		if not player.is_alive():
			break
	touch(0, Vector2(140, 250), false)
	check(feint_then_aim, "a rushed gun enemy feints, then shoots")

	# 30. COVER with a gun enemy: it hides for a moment, then comes out shooting.
	tracker.blocked_by_room[room] = [&"LONG_RANGE"]
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	guard.carried_weapon = load("res://data/weapons/pistol.tres")
	player.equip(load("res://data/weapons/pistol.tres"), -1)
	player.global_position = Vector2(364, 150)
	var covered := false
	var came_out := false
	for i in 300:
		await wait_frames(1)
		if guard._bark_text == "COVER":
			covered = true
		if covered and guard.state == 7:
			came_out = true
			break
		if not player.is_alive():
			came_out = covered
			break
	check(covered and came_out, "a gun enemy hides (COVER), then comes out shooting")
	tracker.clear_room(room)

	# 31. The machine gun fires on its own while you hold the aim stick.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	main.get_node("GruntGuard").free()
	var mg: WeaponData = load("res://data/weapons/machine_gun.tres")
	player.equip(mg, -1)
	touch(1, Vector2(420, 300), true)
	drag(1, Vector2(460, 300))
	await wait_frames(40)
	touch(1, Vector2(460, 300), false)
	await wait_frames(2)
	check(mg.automatic and player.ammo <= mg.ammo - 5, "holding the aim stick keeps the machine gun firing (%d of %d left)" % [player.ammo, mg.ammo])

	# 32. An enemy with a machine gun fires a burst.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	guard.carried_weapon = mg
	player.global_position = guard.global_position + Vector2(-50, 0)
	var burst := 0
	for i in 60:
		await wait_frames(1)
		burst = maxi(burst, guard._burst_left)
		if guard._struck and guard.state == 7:
			break
	check(burst == guard.BURST_SHOTS - 1, "a machine gun enemy fires a burst (%d more after the first)" % burst)

	# 33. THROW: your weapon flies at the enemy and knocks it down, then lies there.
	await reload_room(true)
	main = current_scene
	player = main.get_node("Player")
	main.get_node("GruntPatrol").free()
	guard = main.get_node("GruntGuard")
	player.equip(load("res://data/weapons/pistol.tres"), 3)
	player.global_position = guard.global_position + Vector2(-45, 0)
	player.facing = Vector2.RIGHT
	player.request_throw(Vector2.ZERO)
	check(player.weapon.id == &"fists", "throwing leaves you with your fists")
	var downed := false
	for i in 30:
		await wait_frames(1)
		if guard.is_down():
			downed = true
			break
	check(downed, "the thrown gun knocks the enemy down")
	await wait_frames(20)
	var thrown_gun := root.get_tree().get_nodes_in_group("pickups").filter(func(p): return p.name != "PistolPickup" and p.weapon.id == &"pistol")
	check(thrown_gun.size() == 1 and thrown_gun[0].ammo == 3, "the gun lands on the floor with its ammo")

	# 34. Ground finisher: attack while on the downed enemy to smash its head.
	player.global_position = guard.global_position + Vector2(-10, 0)
	await wait_frames(1)
	player.request_attack(Vector2.ZERO)
	check(player.is_finishing(), "attacking on a downed enemy starts the finisher")
	await wait_frames(18)
	check(guard.is_alive() and guard.is_down(), "it takes a moment: the enemy is still down mid-finisher")
	touch(0, Vector2(100, 250), true)
	drag(0, Vector2(140, 250))
	var start_pos: Vector2 = player.global_position
	await wait_frames(10)
	check(player.global_position.distance_to(start_pos) < 1.0, "you can't move during the finisher")
	await wait_frames(12)
	touch(0, Vector2(140, 250), false)
	check(not guard.is_alive() and not player.is_finishing(), "after about 0.6 s the enemy is dead")

	# 35. Attacks move the body; held weapons stay smaller than you.
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	player.global_position = Vector2(200, 200)
	await wait_frames(2)
	var torso: Node2D = player.get_node("Torso")
	player.equip(load("res://data/weapons/machete.tres"), -1)
	var furthest := 0.0
	var arm_frames := {}
	var arms: Sprite2D = player._arms
	await wait_frames(1)
	check(arms.visible and arms.frame == 0, "a machete in hand shows the arms holding it")
	player.request_attack(Vector2.RIGHT)
	for i in 20:
		await physics_frame
		furthest = maxf(furthest, torso.position.dot(player.facing))
		arm_frames[arms.frame] = true
	check(arm_frames.size() == 4, "a swing plays all 4 arm frames (%s)" % [arm_frames.keys()])
	check(furthest > 2.0, "a swing lunges forward (%.1f px)" % furthest)
	await wait_frames(10)
	check(torso.position.length() < 0.01 and absf(angle_difference(torso.rotation, player.facing.angle())) < 0.01, "then it settles back to the aim")
	player.equip(load("res://data/weapons/pistol.tres"), 8)
	var kicked := 0.0
	player.request_attack(Vector2.RIGHT)
	for i in 6:
		await physics_frame
		kicked = minf(kicked, torso.position.dot(player.facing))
	check(kicked < -1.0, "a shot kicks you back (%.1f px)" % kicked)
	player.equip(load("res://data/weapons/fists.tres"), -1)
	await wait_frames(20)
	check(not arms.visible, "bare fists show no arm frames at rest")
	player.request_attack(Vector2.RIGHT)
	await wait_frames(2)
	check(arms.visible, "a punch shows the punching arms")
	var thug = load("res://scenes/enemies/grunt.tscn").instantiate()
	thug.carried_weapon = load("res://data/weapons/machete.tres")
	thug.position = Vector2(400, 60)
	main.add_child(thug)
	await wait_frames(3)
	check(thug._arms.visible and thug._arms.texture.resource_path.ends_with("enemy_machete_swing_4f.png"), "a machete enemy holds its machete in the enemy arm frames")
	var big_gun: WeaponData = load("res://data/weapons/machine_gun.tres")
	check(big_gun.held_size().x <= 10.0, "the biggest held gun is shorter than you are wide (%.0f px)" % big_gun.held_size().x)

	# 36. The machete's blade glints: now and then at rest, often while it moves.
	var machete_data: WeaponData = load("res://data/weapons/machete.tres")
	check(machete_data.blade_shine and not load("res://data/weapons/pistol.tres").blade_shine, "the machete has blade shine, guns don't")
	var lines := [BladeShine.blade_line(machete_data.floor_texture, 1, 0)]
	for f in machete_data.attack_frames:
		lines.append(BladeShine.blade_line(machete_data.attack_overlay, machete_data.attack_frames, f))
		lines.append(BladeShine.blade_line(machete_data.enemy_attack_overlay, machete_data.attack_frames, f))
	check(lines.all(func(l): return l.size() == 2 and l[0].distance_to(l[1]) >= 4.0), "the blade is found on the floor sprite and in every arm frame %s" % [lines.map(func(l): return snappedf(l[0].distance_to(l[1]), 0.1) if l.size() == 2 else -1)])
	var resting := BladeShine.new()
	var rest_glints := 0
	var was_on := false
	for i in 300:   # 5 s
		resting.update(1.0 / 60.0, false)
		if resting.active() and not was_on:
			rest_glints += 1
		was_on = resting.active()
	var moving := BladeShine.new()
	var move_glints := 0
	was_on = false
	for i in 300:
		moving.update(1.0 / 60.0, true)
		if moving.active() and not was_on:
			move_glints += 1
		was_on = moving.active()
	check(rest_glints >= 2 and rest_glints <= 3, "at rest it glints every couple of seconds (%d in 5 s)" % rest_glints)
	check(move_glints >= 10, "while it moves it keeps glinting (%d in 5 s)" % move_glints)

	# 37. A doberman: growls when it spots you, runs you down faster than you
	# can run, bites; one hit kills it and it drops nothing.
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	player.global_position = Vector2(150, 285)
	var dog = load("res://scenes/enemies/grunt.tscn").instantiate()
	dog.is_dog = true
	dog.sheet = null
	dog.settings = load("res://data/dog_settings.tres")
	dog.position = Vector2(250, 285)
	dog.start_facing_degrees = 180.0
	main.add_child(dog)
	await wait_frames(3)
	check(dog.state == 1 and dog._bark_text == "GRR", "the dog growls when it spots you")
	check(dog.settings.chase_speed > player.settings.move_speed, "it runs faster than you")
	var bitten := false
	for i in 120:
		await physics_frame
		if not player.is_alive():
			bitten = true
			break
	check(bitten, "it runs you down and bites")
	await reload_room(false)
	main = current_scene
	player = main.get_node("Player")
	dog = load("res://scenes/enemies/grunt.tscn").instantiate()
	dog.is_dog = true
	dog.sheet = null
	dog.settings = load("res://data/dog_settings.tres")
	dog.position = player.global_position + Vector2(20, 0)
	main.add_child(dog)
	await wait_frames(2)
	var old_pickups := get_nodes_in_group("pickups")
	dog.take_hit(player, Vector2.RIGHT, "melee")
	await wait_frames(10)
	var dropped_by_dog := get_nodes_in_group("pickups").filter(func(p): return not old_pickups.has(p))
	check(not dog.is_alive() and dropped_by_dog.is_empty(), "one hit kills it and it drops nothing")

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

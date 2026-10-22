extends SceneTree
## Checks the HD characters (sharper sprites, people the old size so the
## rooms look big):
## the hero, the suit enemy with the implant code and the cyber doberman
## use the Art Director's frames, walk, attack and stay the right size.
##   godot --headless --script res://tests/hd_characters_test.gd

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
	var player = current_scene.get_node("Player")
	var enemies: Array = root.get_tree().get_nodes_in_group("enemies")
	var people := enemies.filter(func(e): return not e.is_dog)
	var dog = enemies.filter(func(e): return e.is_dog)[0]

	var hero: HdBody = player.get_node("HdBody")
	check(hero != null and hero.texture.resource_path.begins_with("res://assets/characters/hd/hero_"), "the hero uses the HD frames")
	check(hero.material.shader.resource_path.ends_with("outline.gdshader") and hero.material.get_shader_parameter("outline_color") == Color("3ce0c8"), "with the teal outline always on")
	var suit: HdBody = people[0].get_node("HdBody")
	check(suit.texture.resource_path.begins_with("res://assets/characters/hd/enemy_"), "enemies are the HD suit")
	check(suit.material.shader.resource_path.ends_with("implant_code.gdshader"), "with the green implant code running down the suit")
	var dog_body: HdBody = dog.get_node("HdBody")
	check(dog_body.texture.resource_path.begins_with("res://assets/characters/hd/dog_"), "the doberman is the HD cyber dog")

	# Size: the old people's size (Fianso: normal people in big rooms).
	var width: float = 83.0 * 0.459 * HdBody.room_scale   # the walk frame's shoulders, in room pixels
	check(width > 14.5 and width < 17.0, "people are about 16 px across, like the old 15.6 (%.1f)" % width)
	check(is_equal_approx(player.get_node("CollisionShape2D").shape.radius, 7.0) and is_equal_approx(people[0].get_node("CollisionShape2D").shape.radius, 7.0), "bodies are the old size (radius 7)")
	check(is_equal_approx(load("res://data/weapons/fists.tres").reach, 24.0) and is_equal_approx(load("res://data/weapons/machete.tres").reach, 34.0), "fists and machete reach as far as before")
	check(is_equal_approx(people[0].settings.attack_range, 18.0) and is_equal_approx(dog.settings.attack_range, 16.0), "enemies and the dog attack from as far as before")

	# Turning: the frames face down, so the body turns to the aim.
	for e in enemies:
		e.set_physics_process(false)
	player.facing = Vector2.RIGHT
	await wait_frames(2)
	check(is_equal_approx(hero.rotation, -PI / 2.0), "the hero turns to face where he aims")

	# Walk, then punch.
	player.velocity = Vector2.ZERO
	check(hero.current == "hero_idle", "standing still: the idle pose")
	var start: Vector2 = player.global_position
	var walked := []
	for i in 20:
		Input.action_press("move_down")
		await physics_frame
		walked.append(hero.frame)
	Input.action_release("move_down")
	check(hero.current == "hero_walk" and walked.max() != walked.min(), "walking plays the walk frames")
	player.global_position = start
	await wait_frames(10)
	player.request_attack(Vector2.LEFT)
	await wait_frames(2)
	check(hero.current == "hero_punch", "a punch plays the punch frames")
	await wait_frames(30)
	check(hero.current != "hero_punch", "and then it's over")

	# Pistol: gun up when standing still; shooting plays the shot.
	player.equip(load("res://data/weapons/pistol.tres"), 8)
	await wait_frames(3)
	check(hero.current == "hero_pistol" and hero.frame == 0, "holding a pistol, standing: gun up")
	player.request_attack(Vector2.LEFT)
	await wait_frames(3)
	check(hero.current == "hero_pistol" and player._hd_attack == "pistol", "shooting plays the pistol frames")

	# The dog trots and bites.
	dog.set_physics_process(true)
	dog.velocity = Vector2(80, 0)
	dog._update_hd(0.1)
	check(dog_body.current == "dog_trot", "the dog trots when it moves")
	dog._start_hd_attack()
	dog._update_hd(0.05)
	check(dog_body.current == "dog_bite", "and bites when it attacks")

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

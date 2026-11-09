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
	check(hero != null and hero.texture.resource_path.begins_with("res://assets/characters/pixel/hero_") and hero.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "the hero uses the pixel-art frames, unsmoothed")
	check(hero.material.shader.resource_path.ends_with("outline.gdshader") and hero.material.get_shader_parameter("outline_color") == Color("3ce0c8"), "with the teal outline always on")
	var suit: HdBody = people[0].get_node("HdBody")
	check(suit.texture.resource_path.begins_with("res://assets/characters/pixel/enemy_"), "enemies are the pixel suit")
	check(suit.material.shader.resource_path.ends_with("implant_code.gdshader"), "with the green implant code running down the suit")
	var dog_body: HdBody = dog.get_node("HdBody")
	check(dog_body.texture.resource_path.begins_with("res://assets/characters/pixel/dog_"), "the doberman is the pixel cyber dog")

	# Size: one sprite pixel = one screen pixel at the 3x camera (crisp), and
	# people the size the houses were built for; the dog stays 1.1 m.
	check(is_equal_approx(hero.scale.x * 3.0, 1.0) and is_equal_approx(dog_body.scale.x * 3.0, 1.0), "people and the dog drawn 1 sprite px = 1 screen px (the same pixels as the rooms)")
	var hero_shape = player.get_node("CollisionShape2D")
	var dog_shape = dog.get_node("CollisionShape2D")
	check(hero_shape.shape is CapsuleShape2D and absf(hero_shape.shape.radius - 7.33) < 0.1 and absf(dog_shape.shape.height - 34.0) < 0.1, "bodies are shaped like their pictures (person 14.7 px wide, dog 34 px long)")
	player._hd.face(Vector2.RIGHT)
	check(is_equal_approx(hero_shape.rotation, player._hd.rotation) and hero_shape.position.x > 0.0, "and turn with them")
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

	# The picture never reaches outside the body (so never into a wall or
	# furniture): every opaque pixel of the moving and aiming frames.
	for owner in [player, people[0], dog]:
		var body: HdBody = owner.get_node("HdBody")
		var shape: CollisionShape2D = owner.get_node("CollisionShape2D")
		var anims: Array = ["idle", "trot"] if body.who == "dog" else ["idle", "walk", "pistol", "machinegun"]
		var worst := 0.0
		for anim in anims:
			var info: Dictionary = body._info(anim)
			var image: Image = HdBody._texture(info.file).get_image()
			if image.is_compressed():
				image.decompress()
			var s: float = float(info.game_scale) * body.size()
			for f in int(info.frames):
				for y in range(0, int(info.cell_h), 1):
					for x in range(0, int(info.cell_w), 1):
						if image.get_pixel(f * int(info.cell_w) + x, y).a < 0.5:
							continue
						# Frames face down: sprite x/y in body space; the capsule runs along y.
						var p := (Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(info.pivot[0], info.pivot[1])) * s
						var middle := float(HdBody.BODY_SHAPES[body.who][2]) * body.size()
						var r: float = shape.shape.radius
						var half: float = shape.shape.height / 2.0 - r
						var along := clampf(p.y - middle, -half, half)
						worst = maxf(worst, p.distance_to(Vector2(0, middle + along)) - r)
		check(worst <= 1.0, "%s: the picture stays inside the body (sticks out at most %.1f px)" % [body.who, worst])

	print("\n%s (%d failure(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures])
	quit(failures)

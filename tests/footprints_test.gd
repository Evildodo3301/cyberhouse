extends SceneTree
## Bloody footprints: walk through blood and you leave prints that fade out
## after 10 m (Fianso); enemies and dogs too; the blood setting is respected.
##   godot --headless --script res://tests/footprints_test.gd

var failures := 0
## Loaded after the scene is up: the script uses the Game autoload.
var FEET: Script


func check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok:
		failures += 1


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


## Walks `feet` from `start` along +x for `distance` px, 1 px a frame-step.
func walk(feet, walker: Node2D, start: Vector2, distance: float) -> void:
	for i in int(distance):
		feet.update(walker, start + Vector2(i + 1, 0), Vector2.RIGHT)


func _initialize() -> void:
	change_scene_to_file("res://scenes/levels/level_01.tscn")
	await process_frame
	await process_frame
	await wait_frames(3)
	FEET = load("res://scripts/fx/bloody_feet.gd")
	var game = root.get_node("Game")
	var gore = root.get_tree().get_first_node_in_group("gore")
	var player = current_scene.get_node("Player")
	for e in root.get_tree().get_nodes_in_group("enemies"):
		e.set_physics_process(false)
	game.blood_level = game.BloodLevel.FULL

	# A kill on open floor in the lounge: wait for the pool to finish.
	var spot := Vector2(372, 335)
	check(not gore.is_bloody(spot), "clean floor first")
	gore.add_kill(spot, Vector2.LEFT, Color.BLACK, "melee")   # spray goes left, away from the walk
	await wait_frames(30)
	check(gore.is_bloody(spot + Vector2.LEFT * 4.0), "the spreading pool counts as blood straight away")
	await wait_frames(400)
	check(gore.get_children().filter(func(c): return c.get_script() and c.get_script().get_global_name() == &"DyingBody").is_empty() and gore.is_bloody(spot + Vector2.LEFT * 4.0), "and so does the finished pool, painted into the floor")

	# Step in it, then walk away.
	var feet = FEET.new()
	feet.update(player, spot + Vector2.LEFT * 4.0, Vector2.RIGHT)
	check(feet.is_wet(), "stepping in blood wets your soles")
	var before = gore.footprint_count
	var out := spot + Vector2(60, 0)   # off the pool and its spray
	walk(feet, player, out, 40.0)
	check(gore.footprint_count - before == 5, "walking leaves a print every step (%d in 40 px)" % (gore.footprint_count - before))
	var first_alpha = gore.last_footprint_alpha
	walk(feet, player, out + Vector2(40, 0), 200.0)
	check(gore.last_footprint_alpha < first_alpha * 0.4, "the prints fade as you go (%.2f -> %.2f)" % [first_alpha, gore.last_footprint_alpha])
	walk(feet, player, out + Vector2(240, 0), 200.0)
	check(not feet.is_wet() and gore.footprint_count - before < 40, "gone after 10 m (300 px): %d prints in all" % (gore.footprint_count - before))
	var after = gore.footprint_count
	walk(feet, player, out + Vector2(440, 0), 100.0)
	check(gore.footprint_count == after and not feet.is_wet(), "clean soles leave nothing")

	# Dogs leave paw prints, with a shorter stride.
	var paws = FEET.new("dog")
	paws.update(player, spot + Vector2.LEFT * 4.0, Vector2.RIGHT)
	before = gore.footprint_count
	walk(paws, player, out, 36.0)
	check(paws.paws and gore.footprint_count - before == 6, "dogs leave paw prints (%d in 36 px)" % (gore.footprint_count - before))

	# Enemies and dogs carry their own pair of feet.
	var enemies: Array = root.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		e._physics_process(0.016)
	check(enemies.all(func(e): return e._feet != null and e._feet.paws == e.is_dog), "every enemy has feet, dogs paws")

	# Blood setting.
	game.blood_level = game.BloodLevel.REDUCED
	var reduced = FEET.new()
	reduced.update(player, spot + Vector2.LEFT * 4.0, Vector2.RIGHT)
	before = gore.footprint_count
	walk(reduced, player, out, 8.0)
	var reduced_alpha = gore.last_footprint_alpha
	walk(reduced, player, out + Vector2(8, 0), 160.0)
	check(reduced_alpha < first_alpha and not reduced.is_wet(), "REDUCED blood: fainter prints, gone in half the distance")
	game.blood_level = game.BloodLevel.OFF
	var off = FEET.new()
	off.update(player, spot + Vector2.LEFT * 4.0, Vector2.RIGHT)
	before = gore.footprint_count
	walk(off, player, out, 60.0)
	check(gore.footprint_count == before and not off.is_wet(), "OFF blood: no prints at all")
	game.blood_level = game.BloodLevel.FULL

	# The real player picks it up by walking.
	player.global_position = spot + Vector2.LEFT * 4.0
	player.velocity = Vector2.ZERO
	player._feet.update(player, player.global_position, Vector2.RIGHT)
	check(player._feet.is_wet(), "the player's own feet get bloody")

	print("\nALL PASSED (0 failure(s))" if failures == 0 else "\nSOME FAILED (%d failure(s))" % failures)
	quit(failures)

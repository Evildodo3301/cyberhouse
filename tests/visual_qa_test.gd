extends SceneTree
## QA: catches the visual bugs you only see by eye, before a preview goes out.
##   1. People hidden UNDER furniture (the sofa or table drawn over them).
##   2. People drawn ON furniture (standing on the sofa or in the table).
##   3. Real-life size: every piece of furniture, the doors and the dog
##      compared with a person, using real-world sizes (see SIZES).
##   4. Every room and everyone in it can be reached on foot.
##   5. Animations: no frame jumps (sliding / jitter) and the character
##      stays the same size from one animation to the next.
## It sweeps a person (and the dog) over every spot they can stand on, in
## every direction they can face, using the real HD frames.
##   godot --headless --script res://tests/visual_qa_test.gd
##   godot --headless --script res://tests/visual_qa_test.gd -- res://scenes/levels/level_01.tscn
## With a window (xvfb-run ... --rendering-driver opengl3, no --headless) it
## also saves a close-up picture of every problem to user://visual_qa/.
## FAIL = Fianso would see it; WARN = worth a human look.

const LEVELS := [
	"res://scenes/levels/level_01.tscn",
	"res://scenes/levels/level_01_floor2.tscn",
	"res://scenes/levels/level_02.tscn",
]
## A person's shoulders, seen from above, in metres (suit jacket included).
const PERSON_WIDTH_M := 0.5
## Real rooms in square metres (a mansion: generous, but not a sports hall).
## The first kind found among a room's furniture names the room; earlier wins.
const ROOM_M2 := {
	"bathroom": [3, 18],
	"kitchen": [8, 40],
	"bedroom": [9, 45],
	"office": [8, 35],
	"dining room": [10, 45],
	"living room": [15, 90],
	"room": [2, 120],
}
const ROOM_KIND_BY_PIECE := {
	"toilet": "bathroom", "bath": "bathroom", "tub": "bathroom", "shower": "bathroom", "sink": "bathroom",
	"kitchen": "kitchen", "fridge": "kitchen", "stove": "kitchen",
	"bed": "bedroom",
	"exec_desk": "office", "office": "office",
	"dining": "dining room",
	"sofa": "living room",
}
## A corridor or doorway narrower than this is not a walkway in a real home.
const ROOM_NARROWEST_M := 0.9
## Openings narrower than this split two rooms (doorways, archways).
const ROOM_GAP_M := 1.8
## Enemies fall this far along the hit (grunt.gd: add_kill at position + direction * 8).
const CORPSE_SHOVE := 8.0
## Real-life sizes seen from above, in metres: [long side min, max, short side min, max].
## The first key found in a piece's name wins, so longer names go first.
const SIZES := {
	"plant": [0.3, 1.0, 0.3, 1.0],   # before "bed": plant_bedroom_l is a plant
	"statue": [0.4, 1.2, 0.4, 1.2],
	"lamp": [0.3, 0.8, 0.3, 0.8],
	"dog_bed": [0.6, 1.2, 0.5, 1.0],   # before "bed"
	"billiard": [2.4, 3.0, 1.3, 1.7],
	"dining_set": [1.8, 3.4, 1.0, 2.2],
	"dining_table": [1.6, 2.6, 0.8, 1.2],
	"kitchen_island": [1.5, 3.2, 0.8, 1.4],
	"coffee_table": [0.9, 1.6, 0.5, 1.0],
	"exec_desk": [1.4, 2.4, 0.7, 1.2],
	"desk_chair": [0.5, 0.8, 0.5, 0.8],
	"side_table": [0.4, 0.8, 0.4, 0.8],
	"globe_table": [0.4, 0.8, 0.4, 0.8],
	"vase_table": [0.4, 0.8, 0.4, 0.8],
	"console": [0.9, 2.0, 0.3, 0.6],
	"loveseat": [1.3, 1.8, 0.7, 1.0],
	"sofa_side": [1.4, 2.4, 0.7, 1.1],
	"sofa": [1.8, 2.8, 0.7, 1.1],
	"armchair": [0.7, 1.1, 0.7, 1.1],
	"wingback": [0.7, 1.1, 0.7, 1.1],
	"chair": [0.4, 0.75, 0.4, 0.75],
	"lounger": [1.8, 2.2, 0.6, 0.9],
	"bed": [1.9, 2.4, 1.4, 2.3],
	"fridge": [0.6, 0.95, 0.6, 0.95],
	"cabinet": [0.6, 1.6, 0.4, 0.7],
	"globe": [0.4, 0.9, 0.4, 0.9],
}
## A doberman nose to tail, and across its back (metres).
const DOG_LENGTH_M := [0.9, 1.3]
## A door you walk through alone (metres); double doors are twice that.
const DOOR_M := [0.75, 1.1]
## Areas nobody is meant to walk into, by a tile inside them (Fianso
## 2026-10-22: the floor 1 garden and pool stay out of reach; on floor 2 the
## same outdoor area is below the balcony).
const FENCED_OFF := {
	"level_01": [Vector2i(0, 0)],
	"level_01_floor2": [Vector2i(0, 0)],
}
## Furniture a dog may run under (Fianso: dogs are shorter than a table).
const DOG_FITS_UNDER := ["table", "desk", "dining"]   # and plain chairs (not armchairs)
## Every animation a body can show next to a wall.
const MOVE_ANIMS := ["idle", "walk", "trot"]
const ATTACK_ANIMS := ["punch", "pistol", "shotgun", "machinegun", "machete", "bite"]
## More than this many of a body's pixels drawn into a wall = FAIL.
const WALL_LIMIT := 3
## More than this many of a person's pixels covered by furniture = FAIL.
const HIDDEN_LIMIT := 6
## Fianso's rule: furniture never overlaps a person (player or enemy), either
## way round. Only dogs may go under furniture (they're shorter than a table).
## More than this many of a person's pixels drawn over furniture = WARN (the
## pieces cut from a picture carry some floor round the edge, so a head just
## below a piece often counts; the pictures show which ones are real).
const ON_TOP_LIMIT := 6
## A walking frame moving the body more than this (room px) = sliding/jitter.
const JITTER_LIMIT := 1.5
## How many directions a body is tried facing at every spot.
const FACINGS := 8

var failures := 0
var warnings := 0
var report: PackedStringArray = []
var shots_dir := "user://visual_qa"
var floor_like: PackedByteArray     # room pixel -> 1 if the top piece there looks like the floor
var base_floor: Image               # picture levels: the floor drawing under the pieces
var floor_texels := 1.0
var corpse_points := {}            # "hero2" -> drawn points of that death and dead pose, unturned             # texels of base_floor per room px


func check(ok: bool, label: String, warn_only := false) -> void:
	var tag := "PASS  " if ok else ("WARN  " if warn_only else "FAIL  ")
	print(tag + label)
	report.append(tag + label)
	if not ok:
		if warn_only:
			warnings += 1
		else:
			failures += 1


func note(text: String) -> void:
	print("      " + text)
	report.append("      " + text)


func wait_frames(n: int) -> void:
	for i in n:
		await physics_frame


func _initialize() -> void:
	var levels: Array = LEVELS
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		levels = args
	var rendering := DisplayServer.get_name() != "headless"
	if rendering:
		DirAccess.make_dir_recursive_absolute(shots_dir)
	check_animations()
	for path in levels:
		await check_level(path, rendering)
	print("\n%s (%d failure(s), %d warning(s))" % ["ALL PASSED" if failures == 0 else "SOME FAILED", failures, warnings])
	var file := FileAccess.open("user://visual_qa_report.txt", FileAccess.WRITE)
	if file:
		file.store_string("\n".join(report) + "\n")
		print("report: " + ProjectSettings.globalize_path("user://visual_qa_report.txt"))
	quit(failures)


# --- 5. Animations ---------------------------------------------------------

## Opaque pixels of one frame, in room px around the body's centre, facing down.
func frame_pixels(body: HdBody, anim: String, index: int) -> Array:
	body.show_anim(anim, index)
	var image := body.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var cell := Vector2(image.get_width() / body.hframes, image.get_height())
	var points := []
	for y in range(0, int(cell.y), 2):
		for x in range(0, int(cell.x), 2):
			if image.get_pixel(int(cell.x) * index + x, y).a > 0.5:
				points.append((Vector2(x, y) + Vector2.ONE - cell / 2.0 + body.offset) * body.scale)
	return points


func check_animations() -> void:
	print("\n== Animations ==")
	report.append("\n== Animations ==")
	for who in ["hero", "enemy", "dog"]:
		var body := HdBody.new()
		body.setup(who)
		var areas := {}
		for anim in ["idle", "walk", "trot", "punch", "pistol", "shotgun", "machinegun", "machete", "bite"]:
			if not body.has_anim(anim):
				continue
			var count := body.frame_count(anim)
			var centres: Array[Vector2] = []
			var frame_areas: Array[float] = []
			for i in count:
				var points := frame_pixels(body, anim, i)
				var sum := Vector2.ZERO
				for p in points:
					sum += p
				centres.append(sum / maxf(points.size(), 1.0))
				frame_areas.append(points.size() * 4.0 * body.scale.x * body.scale.y)
			areas[anim] = frame_areas.min()
			if anim in ["walk", "trot"]:
				var worst := 0.0
				for i in count:
					worst = maxf(worst, centres[i].distance_to(centres[(i + 1) % count]))
				check(worst <= JITTER_LIMIT, "%s %s: the body doesn't jump between frames (biggest jump %.1f px)" % [who, anim, worst], true)
		var base: float = areas.get("walk", areas.get("trot", 0.0))
		for anim in areas:
			var ratio: float = areas[anim] / base
			check(ratio > 0.7 and ratio < 1.6, "%s %s: same size as walking (%.0f%% of the walk's body)" % [who, anim, ratio * 100.0], true)
		body.free()


# --- one level ---------------------------------------------------------------

func check_level(path: String, rendering: bool) -> void:
	print("\n== %s ==" % path)
	report.append("\n== %s ==" % path)
	root.get_node("TacticTracker").clear_room(StringName(path.get_file().get_basename()))
	change_scene_to_file(path)
	await process_frame
	await process_frame
	await wait_frames(3)
	var level := current_scene
	var map = level.get_node("LevelMap")
	var player = level.get_node("Player")
	var enemies: Array = root.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		e.set_physics_process(false)
		e.set_process(false)
	player.set_physics_process(false)
	var size := Vector2i(map.size_px.ceil())

	# Everything drawn on the floor that a person can stand next to.
	var pieces: Array = []
	for group in ["picture_pieces", "fancy_furniture"]:
		for node in root.get_tree().get_nodes_in_group(group):
			if node is Sprite2D and node.z_index >= 0 and node.visible:
				pieces.append(node)
	var owner_of := PackedInt32Array()   # room pixel -> index of the piece drawn there (top one)
	owner_of.resize(size.x * size.y)
	owner_of.fill(-1)
	# Pieces cut out of a picture are rectangles with some floor around the
	# furniture. Pixels that look like the floor underneath aren't furniture:
	# a person over them looks fine (but under them he's still cut off).
	floor_like = PackedByteArray()
	floor_like.resize(size.x * size.y)
	base_floor = null
	if map.picture:
		base_floor = map.picture.get_image()
		floor_texels = base_floor.get_width() / float(size.x)
		if base_floor.is_compressed():
			base_floor.decompress()
	var names: Array[String] = []
	for piece in pieces:
		var n := String(piece.name)
		names.append(n.to_snake_case() if not n.begins_with("@") else piece.texture.resource_path.get_file().get_basename())
	var piece_rects: Array[Rect2i] = []
	var piece_pixels: Array[int] = []
	for i in pieces.size():
		var r := paint_piece(pieces[i], i, owner_of, size, pieces)
		piece_rects.append(r[0])
		piece_pixels.append(r[1])

	# The person and the dog: every pixel they can cover, any frame, any direction.
	var person_masks := body_masks(player.get_node_or_null("HdBody"), ["idle", "walk"])
	var person_size: int = person_masks[0].size()
	var dogs := enemies.filter(func(e): return e.is_dog)
	var dog_masks := body_masks(dogs[0].get_node_or_null("HdBody"), ["idle", "trot"]) if not dogs.is_empty() else []

	var person_px := shoulder_width(player.get_node_or_null("HdBody"))
	var px_per_m := person_px / PERSON_WIDTH_M
	note("a person is %.1f px across the shoulders, so 1 m = %.1f px" % [person_px, px_per_m])

	# --- 4. Reachability (doors count as open) ---
	var player_radius: float = smallest_radius(player)
	var reach := flood(player, player.global_position, player_radius, player.collision_mask & ~16, size)
	# Bodies are capsules that turn with the picture: where one can't face a
	# way without hitting something, it is never drawn that way there.
	var player_blocked := blocked_by_facing(player, reach)
	var dogs_early := enemies.filter(func(e): return e.is_dog)
	var dog_reach := {}
	var dog_blocked := []
	if not dogs_early.is_empty():
		var dog0: Node2D = dogs_early[0]
		dog_reach = flood(dog0, dog0.global_position, smallest_radius(dog0), dog0.collision_mask & ~16, size)
		dog_blocked = blocked_by_facing(dog0, dog_reach)
	note("%d spots a person can stand on" % reach.size())
	var unreached_rooms := []
	var rooms := {}
	for at in map._room_of_tile:
		rooms[map._room_of_tile[at]] = rooms.get(map._room_of_tile[at], []) + [at]
	for room in rooms:
		var fenced: Array = FENCED_OFF.get(path.get_file().get_basename(), [])
		if fenced.any(func(at): return map._room_of_tile.get(at, -1) == room):
			continue
		# Slivers too narrow for anyone to stand in (a strip outside the walls) don't count.
		if not rooms[room].any(func(at): return body_fits(player, (Vector2(at) + Vector2(0.5, 0.5)) * map.tile_px, player_radius, player.collision_mask & ~16)):
			continue
		var hit := false
		for at in rooms[room]:
			var c: Vector2 = (Vector2(at) + Vector2(0.5, 0.5)) * map.tile_px
			if reach.has(Vector2i(int(c.x) / 2 * 2, int(c.y) / 2 * 2)) or near_reached(reach, c, map.tile_px):
				hit = true
				break
		if not hit:
			var lo: Vector2i = rooms[room][0]
			var hi: Vector2i = rooms[room][0]
			for at in rooms[room]:
				lo = lo.min(at)
				hi = hi.max(at)
			unreached_rooms.append("%d tiles between tile %s and %s" % [rooms[room].size(), lo, hi])
	check(unreached_rooms.is_empty(), "every area of the map can be walked into, apart from the ones fenced off on purpose %s" % [unreached_rooms], true)
	var lost := []
	for thing in enemies + root.get_tree().get_nodes_in_group("pickups"):
		if not near_reached(reach, thing.global_position, 10.0):
			lost.append("%s at %s" % [thing.name, (thing.global_position / map.tile_px).floor()])
	check(lost.is_empty(), "every enemy and weapon can be walked up to %s" % [lost])

	# --- 1 + 2. People and furniture ---
	if pieces.is_empty():
		note("no furniture art on this map yet (stand-in blocks): skipping the furniture sweep")
	else:
		# Is the person drawn above the whole furniture layer (not Y-sorted
		# with it)? Then furniture can never be drawn over him.
		var people: Array = [player] + enemies.filter(func(e): return not e.is_dog)
		var under := people.filter(func(who): return not drawn_above_furniture(who, map))
		var people_on_top := under.is_empty()
		check(people_on_top or not map.has_node("Furniture"), "the player and every enemy are drawn above the furniture layer %s" % [under.map(func(who): return who.name)])
		var worst := sweep(reach, person_masks, owner_of, size, pieces, people_on_top, player_blocked)
		var hidden_bad := []
		var on_top_bad := []
		for i in pieces.size():
			var w: Dictionary = worst[i]
			if w.hidden > HIDDEN_LIMIT:
				hidden_bad.append(i)
			if w.on_top > ON_TOP_LIMIT:
				on_top_bad.append(i)
		check(hidden_bad.is_empty(), "nobody can be hidden under furniture (%d piece(s) can cover a person)" % hidden_bad.size())
		for i in hidden_bad:
			var w: Dictionary = worst[i]
			note("%s is drawn over up to %d%% of a person standing at %s facing %s (tile %s)" % [names[i], int(100.0 * w.hidden / person_size), w.hidden_at, compass(w.hidden_facing), (w.hidden_at / map.tile_px).floor()])
		# Mostly a head touching the bottom edge of a piece: look at the pictures.
		check(on_top_bad.is_empty(), "nobody is drawn over furniture art (%d piece(s))" % on_top_bad.size(), true)
		for i in on_top_bad:
			var w: Dictionary = worst[i]
			note("%s: up to %d%% of a person drawn over it at %s facing %s" % [names[i], int(100.0 * w.on_top / person_size), w.on_top_at, compass(w.on_top_facing)])
		if not dog_masks.is_empty():
			var dog_worst := sweep(dog_reach, dog_masks, owner_of, size, pieces, false, dog_blocked)
			var dog_under := range(pieces.size()).filter(func(i): return dog_worst[i].hidden > HIDDEN_LIMIT)
			# Fianso: dogs may go under tables (they're shorter), but never push
			# into a sofa, a cabinet or a plant.
			var under_table := func(i): return DOG_FITS_UNDER.any(func(k): return names[i].contains(k)) or (names[i].contains("chair") and not names[i].contains("armchair") and not names[i].contains("wingback"))
			var dog_into := dog_under.filter(func(i): return not under_table.call(i))
			check(dog_into.is_empty(), "the dog never pushes into furniture it can't fit under (%d piece(s))" % dog_into.size())
			for i in dog_into:
				note("%s: up to %d px of the dog inside it at %s facing %s" % [names[i], dog_worst[i].hidden, dog_worst[i].hidden_at, compass(dog_worst[i].hidden_facing)])
				if rendering:
					await snapshot(level, dogs[0], dog_worst[i].hidden_at, dog_worst[i].hidden_facing, "%s_dog_into_%s" % [path.get_file().get_basename(), names[i]])
			note("the dog can go under (allowed): %s" % [", ".join(dog_under.filter(under_table).map(func(i): return names[i]))])
		if rendering:
			for i in hidden_bad:
				await snapshot(level, player, worst[i].hidden_at, worst[i].hidden_facing, "%s_under_%s" % [path.get_file().get_basename(), names[i]])
			for i in on_top_bad:
				await snapshot(level, player, worst[i].on_top_at, worst[i].on_top_facing, "%s_over_%s" % [path.get_file().get_basename(), names[i]])

	# --- 6. Walls: no person or dog drawn into a wall, in any pose or direction ---
	var wall := PackedByteArray()   # room pixel -> 1 wall or outside, 2 pool
	wall.resize(size.x * size.y)
	for y in size.y:
		for x in size.x:
			var letter: String = map.tile(Vector2i(x, y) / int(map.tile_px))
			if letter in ["#", " "]:
				wall[y * size.x + x] = 1
			elif letter == "~":
				wall[y * size.x + x] = 2
	var near_wall := dilate(wall, size, 40)
	await check_walls("a person walking", player, reach, body_masks(player.get_node_or_null("HdBody"), MOVE_ANIMS), wall, near_wall, size, map, path, rendering, player_blocked)
	await check_walls("a person attacking", player, reach, body_masks(player.get_node_or_null("HdBody"), ATTACK_ANIMS), wall, near_wall, size, map, path, rendering, player_blocked, true)
	if not dogs.is_empty():
		await check_walls("the dog walking", dogs[0], dog_reach, body_masks(dogs[0].get_node_or_null("HdBody"), MOVE_ANIMS), wall, near_wall, size, map, path, rendering, dog_blocked)
		await check_walls("the dog biting", dogs[0], dog_reach, body_masks(dogs[0].get_node_or_null("HdBody"), ATTACK_ANIMS), wall, near_wall, size, map, path, rendering, dog_blocked, true)

	# --- 6b. Bodies: a corpse stays for good, so no part of it, in any death
	# frame or its dead pose, may cover a wall or furniture (Fianso,
	# 2026-10-23). Kill people and dogs at spots by walls and furniture, let the
	# game lay the body out (GoreLayer.fit_corpse) and look at every drawn pixel.
	var gore = root.get_tree().get_first_node_in_group("gore")
	var near_things := wall.duplicate()
	for k in owner_of.size():
		if owner_of[k] >= 0:
			near_things[k] = 1
	near_things = dilate(near_things, size, 24)
	var corpse_cases := [["hero", reach, 0.0, "a dead hero"], ["enemy", reach, CORPSE_SHOVE, "a dead enemy"]]
	if not dogs.is_empty():
		corpse_cases.append(["dog", dog_reach, CORPSE_SHOVE, "a dead dog"])
	for case in corpse_cases:
		if gore == null or not gore.has_method("fit_corpse"):
			note("no GoreLayer.fit_corpse on this map: bodies not checked")
			break
		var body := HdBody.new()
		body.setup(case[0])
		var corpse := {"pixel": case[0], "size": body.size()}
		body.free()
		var spots: Array = case[1].keys().filter(func(p): return near_things[p.y * size.x + p.x] and (p.x + p.y) % 8 == 0)
		var worst_wall := 0
		var worst_furniture := 0
		var worst_at := Vector2.ZERO
		var worst_dir := Vector2.DOWN
		var worst_what := ""
		var bad_spots := 0
		for p in spots:
			for turn in 4:
				var dir := Vector2.DOWN.rotated(TAU * (turn + 0.5 * ((p.x / 8) % 2)) / 4.0)
				var at: Vector2 = Vector2(p) + dir * case[2]
				var fit: Array = gore.fit_corpse(at, dir, corpse)
				var counts := corpse_hits(case[0], fit[2], fit[0], fit[1], float(corpse.size), wall, owner_of, size)
				if counts[0] > WALL_LIMIT or counts[1] > WALL_LIMIT:
					bad_spots += 1
				if counts[0] + counts[1] > worst_wall + worst_furniture:
					worst_wall = counts[0]
					worst_furniture = counts[1]
					worst_at = Vector2(p)
					worst_dir = dir
					worst_what = "death%s" % fit[2]
		check(worst_wall <= WALL_LIMIT, "%s never lies over a wall, any death frame or dead pose (%d spots by walls and furniture, 4 hit directions each; worst %d px at %s hit %s, %s; %d bad)" % [case[3], spots.size(), worst_wall, worst_at, compass(worst_dir), worst_what, bad_spots])
		check(worst_furniture <= WALL_LIMIT, "%s never lies over furniture (worst %d px at %s hit %s)" % [case[3], worst_furniture, worst_at, compass(worst_dir)])

	# --- 7. Pixel size: characters and rooms drawn with pixels the same size ---
	var room_texel := 1.0   # room px per texel of the floor picture / furniture
	if map.picture:
		room_texel = map.size_px.x / float(map.picture.get_width())
	elif not pieces.is_empty():
		room_texel = absf(pieces[0].global_scale.x)
	for who in [player] + dogs.slice(0, 1):
		var hd = who.get_node_or_null("HdBody")
		if hd == null:
			continue
		var body := HdBody.new()
		body.setup(hd.who)
		body.show_anim("walk" if body.has_anim("walk") else "trot", 0)
		var texel: float = absf(body.scale.x)
		body.free()
		var ratio := texel / room_texel
		check(ratio > 0.75 and ratio < 1.33, "%s is drawn with %.2f room px per art pixel, the room with %.2f: %s" % [who.name, texel, room_texel, "the same" if ratio > 0.75 and ratio < 1.33 else "the character is %.1fx sharper than the room" % (1.0 / ratio) if ratio < 1.0 else "the room is %.1fx sharper" % ratio])

	# --- 8. Dying: no size or pixel-size jump from the living body to the corpse ---
	var people_alive := enemies.filter(func(e): return not e.is_dog)
	if not people_alive.is_empty() and people_alive[0].has_method("_corpse"):
		var corpse: Dictionary = people_alive[0]._corpse()
		var hd_alive = people_alive[0].get_node_or_null("HdBody")
		if corpse.has("texture") and hd_alive:
			var body := HdBody.new()
			body.setup(hd_alive.who)
			body.show_anim("walk", 0)
			var alive_texel: float = absf(body.scale.x)
			body.free()
			var image: Image = corpse.texture.get_image()
			if image.is_compressed():
				image.decompress()
			var used := image.get_region(Rect2i(corpse.region)).get_used_rect()
			var corpse_texel: float = corpse.scale
			var lying_m := maxf(used.size.x, used.size.y) * corpse_texel / px_per_m
			var jump := corpse_texel / alive_texel
			check(jump > 0.8 and jump < 1.25, "a corpse is drawn with the same pixel size as the living body (corpse %.2f, alive %.2f room px per art pixel)" % [corpse_texel, alive_texel])
			check(lying_m > 1.4 and lying_m < 2.0, "a corpse is the length of a person lying down: %.2f m (real 1.5-1.9 m)" % lying_m)
		elif corpse.is_empty() or not corpse.has("texture"):
			note("corpses are drawn by code here, not checked")

	# --- 3. Real-life sizes ---
	for i in pieces.size():
		var key := ""
		var n := names[i]
		for k in SIZES:
			if n.contains(k):
				key = k
				break
		if key == "":
			note("%s: no real-life size on the list, not checked" % names[i])
			continue
		var r: Rect2i = piece_rects[i]
		var long_m := maxf(r.size.x, r.size.y) / px_per_m
		var short_m := minf(r.size.x, r.size.y) / px_per_m
		var s: Array = SIZES[key]
		var ok: bool = long_m >= s[0] * 0.85 and long_m <= s[1] * 1.15 and short_m >= s[2] * 0.85 and short_m <= s[3] * 1.15
		var close: bool = long_m >= s[0] * 0.7 and long_m <= s[1] * 1.3 and short_m >= s[2] * 0.7 and short_m <= s[3] * 1.3
		check(ok, "%s is %.2f x %.2f m next to a person (real %s: %.1f-%.1f x %.1f-%.1f m)" % [names[i], long_m, short_m, key, s[0], s[1], s[2], s[3]], close)
	if not dogs.is_empty():
		var dog_len := body_length(dogs[0].get_node("HdBody")) / px_per_m
		check(dog_len >= DOG_LENGTH_M[0] * 0.85 and dog_len <= DOG_LENGTH_M[1] * 1.15, "the doberman is %.2f m long (real: %.1f-%.1f m)" % [dog_len, DOG_LENGTH_M[0], DOG_LENGTH_M[1]])
	var person_len := body_length(player.get_node("HdBody")) / px_per_m
	check(person_len < 1.0, "a person is drawn %.2f m long head to toe, seen from above (a standing person is about 0.5 m; much longer reads as lying on the floor)" % person_len, true)
	for door in root.get_tree().get_nodes_in_group("doors"):
		var w := door_width(door) / px_per_m
		if w > 0.0:
			check(w >= DOOR_M[0] * 0.85 and w <= DOOR_M[1] * 1.15, "door %s is %.2f m wide (real: %.2f-%.2f m per door panel)" % [door.name, w, DOOR_M[0], DOOR_M[1]], true)
	# --- 9. Weapons and blood: same pixel size, never inside or through a wall ---
	var weapon_files := DirAccess.get_files_at("res://data/weapons")
	for file in weapon_files:
		if not file.ends_with(".tres"):
			continue
		var data = load("res://data/weapons/" + file)
		if data == null or data.get("floor_texture") == null:
			continue
		var art: float = data.get("art_scale") if data.get("art_scale") != null else 1.0   # room px per art px
		var ratio := art / room_texel
		check(ratio >= 0.75 and ratio <= 1.33, "%s lying on the floor is drawn with %.2f room px per art pixel, the room with %.2f%s" % [file.get_basename(), art, room_texel, "" if ratio <= 1.33 else ": the weapon is %.1fx coarser" % ratio])
	for thing in root.get_tree().get_nodes_in_group("pickups"):
		var data = thing.get("weapon")
		if data == null or data.floor_texture == null:
			continue
		var tex_size: Vector2 = data.floor_texture.get_size()
		var placed_scale: float = thing.call("floor_scale") if thing.has_method("floor_scale") else 1.0
		var inside := 0
		for y in int(tex_size.y):
			for x in int(tex_size.x):
				var q := Vector2i((thing.global_transform * ((Vector2(x, y) + Vector2(0.5, 0.5) - tex_size / 2.0) * placed_scale)).floor())
				if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y or wall[q.y * size.x + q.x] == 1:
					inside += 1
		check(inside <= WALL_LIMIT, "%s at tile %s lies clear of the walls (%d px inside)" % [thing.name, (thing.global_position / map.tile_px).floor(), inside])
	# Fling every weapon at the nearest wall from spots right next to it, let
	# it slide to a stop, and look at where its picture ends up.
	var wall_spots := []   # [spot, direction to the wall]
	for p in reach:
		if (p.x + 3 * p.y) % 24 != 0:
			continue
		for k in 8:
			var dir := Vector2.from_angle(TAU * k / 8.0)
			var q := Vector2i((Vector2(p) + dir * 20.0).floor())
			if q.x >= 0 and q.y >= 0 and q.x < size.x and q.y < size.y and wall[q.y * size.x + q.x] == 1:
				wall_spots.append([Vector2(p), dir])
				break
	var flung := []
	var level_root: Node = root.get_tree().current_scene
	for file in weapon_files:
		if not file.ends_with(".tres"):
			continue
		var data = load("res://data/weapons/" + file)
		if data == null or data.get("floor_texture") == null:
			continue
		for spot in wall_spots:
			var pickup: Node2D = load("res://scenes/weapons/weapon_pickup.tscn").instantiate()
			pickup.weapon = data
			pickup.ignore_player = true
			level_root.add_child(pickup)
			pickup.fling(spot[0], spot[1])
			flung.append(pickup)
	for i in 90:
		await physics_frame
	var weapon_worst := {}
	for pickup in flung:
		var name: String = pickup.weapon.resource_path.get_file().get_basename()
		var tex_size: Vector2 = pickup.weapon.floor_texture.get_size()
		var scale: float = pickup.call("floor_scale") if pickup.has_method("floor_scale") else 1.0
		var inside := 0
		for y in int(tex_size.y):
			for x in int(tex_size.x):
				var q := Vector2i((pickup.global_transform * ((Vector2(x, y) + Vector2(0.5, 0.5) - tex_size / 2.0) * scale)).floor())
				if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y or wall[q.y * size.x + q.x] == 1:
					inside += 1
		if inside > weapon_worst.get(name, [-1])[0]:
			weapon_worst[name] = [inside, pickup.global_position]
		pickup.queue_free()
	for name in weapon_worst:
		check(weapon_worst[name][0] <= WALL_LIMIT, "a %s flung at a wall stops with all of it outside (%d throws; worst %d px inside at %s)" % [name, wall_spots.size(), weapon_worst[name][0], weapon_worst[name][1].round()])
	# Kill people with their backs to a wall, so the spurt flies at the wall,
	# and watch every drop: none may show up on the far side.
	if gore and gore.has_method("add_kill"):
		var game: Node = root.get_node("Game")
		var keep_blood = game.blood_level
		game.blood_level = game.BloodLevel.FULL
		for spot in wall_spots.slice(0, 120):
			gore.add_kill(spot[0], -spot[1], Color.BLACK, "pistol", {})
		var through := 0
		var through_at := Vector2.ZERO
		for frame in 300:
			await process_frame
			for body in gore.get_children():
				if not body.has_method("_wound"):
					continue
				var from := Vector2i(body._wound().floor())
				for drop in body._drops:
					var to := Vector2i(drop.pos.floor())
					var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
					var crossed := false
					for t in range(1, steps):
						var r := Vector2i((Vector2(from) + Vector2(to - from) * t / steps).round())
						if r.x >= 0 and r.y >= 0 and r.x < size.x and r.y < size.y and wall[r.y * size.x + r.x] == 1:
							crossed = true
						elif crossed:
							through += 1
							through_at = Vector2(to)
							break
		game.blood_level = keep_blood
		check(through == 0, "blood from a spurt never shows on the far side of a wall (%d kills with their backs to a wall; %d drops got through%s)" % [mini(wall_spots.size(), 120), through, "" if through == 0 else ", e.g. at %s" % through_at])

	# Rooms next to a person: a bedroom, a bathroom or a corridor the size of a
	# real one. Picture maps draw their walls in the picture, so a room is a
	# patch of floor someone can stand on, cut at the doors; its kind comes
	# from the furniture in it.
	# Doorways and archways are where the floor narrows: shrink the floor until
	# the gaps close, number the pieces left (the rooms), then grow them back.
	var steps4 := [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]
	var depth := {}   # reach spot -> steps from the edge of the floor
	var edge: Array[Vector2i] = []
	for at in reach:
		if map.tile(at / int(map.tile_px)) == "D" or steps4.any(func(d): return not reach.has(at + d)):
			depth[at] = 0
			edge.append(at)
	while not edge.is_empty():
		var next_edge: Array[Vector2i] = []
		for at in edge:
			for d in steps4:
				var n: Vector2i = at + d
				if reach.has(n) and not depth.has(n):
					depth[n] = depth[at] + 1
					next_edge.append(n)
		edge = next_edge
	var core_steps := int(ROOM_GAP_M * px_per_m / 4.0)   # half the gap, in 2 px steps
	var region := {}   # reach spot -> room number
	var room_spots := []
	for start in reach:
		if region.has(start) or depth.get(start, 0) < core_steps:
			continue
		var todo: Array[Vector2i] = [start]
		region[start] = room_spots.size()
		while not todo.is_empty():
			var at: Vector2i = todo.pop_back()
			for d in steps4:
				var n: Vector2i = at + d
				if reach.has(n) and not region.has(n) and depth.get(n, 0) >= core_steps:
					region[n] = room_spots.size()
					todo.append(n)
		room_spots.append([])
	var grow: Array = region.keys()
	while not grow.is_empty():
		var next_grow := []
		for at in grow:
			for d in steps4:
				var n: Vector2i = at + d
				if reach.has(n) and not region.has(n):
					region[n] = region[at]
					next_grow.append(n)
		grow = next_grow
	for at in region:
		room_spots[region[at]].append(at)
	var kinds := {}   # room number -> kind
	for i in pieces.size():
		var votes := {}
		var r := piece_rects[i].grow(12)
		for y in range(r.position.y / 2 * 2, r.end.y, 2):
			for x in range(r.position.x / 2 * 2, r.end.x, 2):
				if region.has(Vector2i(x, y)):
					votes[region[Vector2i(x, y)]] = votes.get(region[Vector2i(x, y)], 0) + 1
		if votes.is_empty():
			continue
		var room: int = votes.keys().reduce(func(a, b): return a if votes[a] >= votes[b] else b)
		for key in ROOM_KIND_BY_PIECE:
			if names[i].contains(key) and not names[i].contains("dog_bed"):
				var k: String = ROOM_KIND_BY_PIECE[key]
				if not kinds.has(room) or ROOM_M2.keys().find(k) < ROOM_M2.keys().find(kinds[room]):
					kinds[room] = k
				break
	for room in room_spots.size():
		var spots: Array = room_spots[room]
		var lo: Vector2i = spots[0]
		var hi: Vector2i = spots[0]
		for at in spots:
			lo = lo.min(at)
			hi = hi.max(at)
		# Where a person can stand, plus his own width on each side: the floor.
		var w := (hi.x - lo.x + 2 * player_radius) / px_per_m
		var h := (hi.y - lo.y + 2 * player_radius) / px_per_m
		var area := w * h
		if spots.size() < 20:
			continue   # a nook by a door, not a room
		var kind: String = kinds.get(room, "room")
		var want: Array = ROOM_M2[kind]
		var tile := Vector2i(Vector2(lo) / map.tile_px)
		check(area >= want[0] * 0.85 and area <= want[1] * 1.15, "%s at tile %s is %.1f x %.1f m = %.0f m2 next to a person (real %s: %d-%d m2)" % [kind, tile, w, h, area, kind, want[0], want[1]], true)   # rooms are found from the floor shape: look at the picture before calling it wrong
		if minf(w, h) < ROOM_NARROWEST_M:
			check(false, "%s at tile %s is only %.1f m across (a walkway needs at least %.1f m)" % [kind, tile, minf(w, h), ROOM_NARROWEST_M], minf(w, h) >= ROOM_NARROWEST_M * 0.8)


## Marks the piece's opaque pixels in owner_of (the piece drawn on top wins).
## Returns [its outline on the map, its pixel count].
func paint_piece(piece: Sprite2D, index: int, owner_of: PackedInt32Array, size: Vector2i, pieces: Array) -> Array:
	var image := piece.texture.get_image()
	if image.is_compressed():
		image.decompress()
	var region := Rect2i(Vector2i.ZERO, image.get_size())
	if piece.region_enabled:
		region = Rect2i(piece.region_rect)
	var xf := piece.get_global_transform()
	var corner := piece.offset - (Vector2(region.size) / 2.0 if piece.centered else Vector2.ZERO)
	var lo := Vector2i(1 << 20, 1 << 20)
	var hi := Vector2i(-(1 << 20), -(1 << 20))
	var count := 0
	for y in region.size.y:
		for x in region.size.x:
			var colour := image.get_pixel(region.position.x + x, region.position.y + y)
			if colour.a < 0.5:
				continue
			var at := xf * (corner + Vector2(x, y) + Vector2(0.5, 0.5))
			var p := Vector2i(at.floor())
			var inside := p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y
			var is_floor := false
			var under_at := Vector2i((at * floor_texels).floor())   # the floor drawing's texel under it
			if inside and base_floor and under_at.x < base_floor.get_width() and under_at.y < base_floor.get_height():
				var under := base_floor.get_pixelv(under_at)
				is_floor = absf(under.r - colour.r) + absf(under.g - colour.g) + absf(under.b - colour.b) < 0.15
			if not is_floor:
				lo = lo.min(p)
				hi = hi.max(p)
				count += 1
			if not inside:
				continue
			var k := p.y * size.x + p.x
			var was := owner_of[k]
			if was < 0 or draws_after(piece, index, pieces[was], was):
				owner_of[k] = index
				floor_like[k] = 1 if is_floor else 0
	if count == 0:
		return [Rect2i(), 0]
	return [Rect2i(lo, hi - lo + Vector2i.ONE), count]


## True if `who` is always drawn after (above) the map's whole furniture
## layer: not Y-sorted together with it, and later in drawing order.
func drawn_above_furniture(who: CanvasItem, map: Node2D) -> bool:
	var layer := map.get_node_or_null("Furniture") as CanvasItem
	if layer == null or map.y_sort_enabled:
		return false
	var z_who := who.z_index
	var z_layer := layer.z_index
	if z_who != z_layer:
		return z_who > z_layer
	# Same z: drawn in tree order, unless both sit under one Y-sorted parent.
	var parent := who.get_parent()
	while parent != null and parent is CanvasItem:
		if parent.y_sort_enabled and parent.is_ancestor_of(layer):
			return false
		parent = parent.get_parent()
	return who.is_greater_than(layer)


func draws_after(a: Node2D, ia: int, b: Node2D, ib: int) -> bool:
	if a.z_index != b.z_index:
		return a.z_index > b.z_index
	if a.global_position.y != b.global_position.y:
		return a.global_position.y > b.global_position.y
	return ia > ib


## For each of 8 facing directions: the room-pixel offsets (from the body's
## position) the HD body covers, over every frame of `anims`.
func body_masks(real: HdBody, anims: Array) -> Array:
	if real == null:
		return []
	var body := HdBody.new()
	body.setup(real.who)
	var masks := []
	for turn in FACINGS:
		var seen := {}
		var xf := Transform2D(TAU * turn / FACINGS, real.position)
		for anim in anims:
			if not body.has_anim(anim):
				continue
			for i in body.frame_count(anim):
				for p in frame_pixels(body, anim, i):
					seen[Vector2i((xf * p).floor())] = true
		masks.append(seen.keys())
	body.free()
	return masks


## How many drawn pixels of a lying body (every frame of its death and its
## dead pose, as the game draws them) land on [a wall, furniture art].
func corpse_hits(who: String, variant: String, at: Vector2, heading: Vector2, size: float, wall: PackedByteArray, owner_of: PackedInt32Array, map_size: Vector2i) -> Array:
	var key := who + variant
	if not corpse_points.has(key):
		var seen := {}
		for name in [who + "_death" + variant, who + "_dead" + variant]:
			var info := HdBody.info_of(name)
			if info.is_empty():
				continue
			var image: Image = load(HdBody.ANIMS_FILE.get_base_dir().path_join(info.file)).get_image()
			if image.is_compressed():
				image.decompress()
			for f in int(info.frames):
				for y in int(info.cell_h):
					for x in int(info.cell_w):
						if image.get_pixel(f * int(info.cell_w) + x, y).a >= 0.5:
							seen[(Vector2(x, y) + Vector2(0.5, 0.5) - Vector2(info.pivot[0], info.pivot[1])) * float(info.game_scale)] = true
		corpse_points[key] = seen.keys()
	var on_wall := {}
	var on_piece := {}
	var turn := heading.angle() + PI * 0.5
	for point in corpse_points[key]:
		var q := Vector2i((at + (point * size).rotated(turn)).floor())
		if q.x < 0 or q.y < 0 or q.x >= map_size.x or q.y >= map_size.y or wall[q.y * map_size.x + q.x] == 1:
			on_wall[q] = true
		elif owner_of[q.y * map_size.x + q.x] >= 0 and not floor_like[q.y * map_size.x + q.x]:
			on_piece[q] = true
	return [on_wall.size(), on_piece.size()]

## The thinnest wall between two floor pixels, straight across (rows and columns), in px.
func thinnest_wall(wall: PackedByteArray, size: Vector2i) -> int:
	var thin := 1000
	for horizontal in [true, false]:
		var lines: int = size.y if horizontal else size.x
		var along: int = size.x if horizontal else size.y
		for a in lines:
			var run := 0
			var after_floor := false
			for b in along:
				var k: int = a * size.x + b if horizontal else b * size.x + a
				if wall[k] == 1:
					run += 1
				else:
					if after_floor and run > 0:
						thin = mini(thin, run)
					run = 0
					after_floor = wall[k] == 0
	return thin


## Shoulder width in room px: the widest row of the walk's first frame
## (arms hang by the sides there).
func shoulder_width(real: HdBody) -> float:
	var body := HdBody.new()
	body.setup(real.who)
	var points := frame_pixels(body, "walk", 0)
	var lo := 1e9
	var hi := -1e9
	for p in points:
		lo = minf(lo, p.x)
		hi = maxf(hi, p.x)
	body.free()
	return hi - lo


## Head-to-toe (or nose-to-tail) length in room px, standing still.
func body_length(real: HdBody) -> float:
	var body := HdBody.new()
	body.setup(real.who)
	var points := frame_pixels(body, "walk" if body.has_anim("walk") else "trot", 0)
	var lo := 1e9
	var hi := -1e9
	for p in points:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	body.free()
	return hi - lo


func door_width(door: Node2D) -> float:
	var best := 0.0
	for child in door.find_children("*", "CollisionShape2D", true, false):
		if child.shape is RectangleShape2D:
			best = maxf(best, maxf(child.shape.size.x, child.shape.size.y))
	return best


## Every spot (on a 2 px grid) a body of `radius` can stand on and walk to
## from `start`, with doors open.
func flood(body: Node2D, start: Vector2, radius: float, mask: int, size: Vector2i) -> Dictionary:
	var space: PhysicsDirectSpaceState2D = body.get_world_2d().direct_space_state
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.collision_mask = mask
	q.exclude = [body.get_rid()]
	var free_at := func(p: Vector2i) -> bool:
		q.transform = Transform2D(0.0, Vector2(p))
		return space.intersect_shape(q, 1).is_empty()
	var first := Vector2i(int(start.x) / 2 * 2, int(start.y) / 2 * 2)
	var seen := {}
	if not free_at.call(first):
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			if free_at.call(first + d):
				first += d
				break
	seen[first] = true
	var todo: Array[Vector2i] = [first]
	while not todo.is_empty():
		var p: Vector2i = todo.pop_back()
		for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
			var n: Vector2i = p + d
			if seen.has(n) or n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y:
				continue
			if free_at.call(n):
				seen[n] = true
				todo.append(n)
	return seen


## The body's narrowest half-width: a circle this size fits wherever the
## body fits facing some way (capsules turn with the picture).
func smallest_radius(body: Node2D) -> float:
	var shape: Shape2D = body.get_node("CollisionShape2D").shape
	if shape is CircleShape2D or shape is CapsuleShape2D:
		return shape.radius
	if shape is RectangleShape2D:
		return minf(shape.size.x, shape.size.y) * 0.5
	return 4.0


func body_fits(body: Node2D, at: Vector2, radius: float, mask: int) -> bool:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = circle
	q.collision_mask = mask
	q.exclude = [body.get_rid()]
	q.transform = Transform2D(0.0, at)
	return body.get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


func compass(direction: Vector2) -> String:
	return ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"][posmod(roundi(direction.angle() / (TAU / 8.0)), 8)]


func near_reached(reach: Dictionary, at: Vector2, within: float) -> bool:
	var c := Vector2i(int(at.x) / 2 * 2, int(at.y) / 2 * 2)
	var steps := int(within / 2.0)
	for dy in range(-steps, steps + 1):
		for dx in range(-steps, steps + 1):
			if reach.has(c + Vector2i(dx, dy) * 2):
				return true
	return false


## For each piece: the most of a person it can draw over (hidden) and the
## most of a person drawn over it (on_top), and where.
func sweep(reach: Dictionary, masks: Array, owner_of: PackedInt32Array, size: Vector2i, pieces: Array, on_top_always := false, blocked: Array = []) -> Array:
	var worst := []
	for i in pieces.size():
		worst.append({"hidden": 0, "hidden_at": Vector2.ZERO, "hidden_facing": Vector2.DOWN, "on_top": 0, "on_top_at": Vector2.ZERO, "on_top_facing": Vector2.DOWN})
	var reach_px := 0
	for m in masks.reduce(func(a, b): return a + b, []):
		reach_px = maxi(reach_px, maxi(absi(m.x), absi(m.y)))
	var near := PackedByteArray()   # pixels within reach of some furniture
	near.resize(size.x * size.y)
	for k in owner_of.size():
		if owner_of[k] >= 0:
			var x := k % size.x
			var y := k / size.x
			for yy in range(maxi(0, y - reach_px), mini(size.y, y + reach_px + 1), 2):
				near[yy * size.x + x] = 1
	var near2 := near.duplicate()
	for y in size.y:
		for x in size.x:
			if near[y * size.x + x]:
				for xx in range(maxi(0, x - reach_px), mini(size.x, x + reach_px + 1), 2):
					near2[y * size.x + xx] = 1
	var hidden := {}
	var on_top := {}
	for p in reach:
		if not near2[p.y * size.x + p.x]:
			continue
		for f in masks.size():
			if not blocked.is_empty() and blocked[f].has(p):
				continue
			hidden.clear()
			on_top.clear()
			for m in masks[f]:
				var q: Vector2i = p + m
				if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y:
					continue
				var k := q.y * size.x + q.x
				var i := owner_of[k]
				if i < 0:
					continue
				# Y-sort: whoever's base (position) is lower down is drawn later, on top.
				if not on_top_always and float(p.y) < pieces[i].global_position.y:
					hidden[i] = hidden.get(i, 0) + 1
				elif not floor_like[k]:
					on_top[i] = on_top.get(i, 0) + 1
			for i in hidden:
				if hidden[i] > worst[i].hidden:
					worst[i].hidden = hidden[i]
					worst[i].hidden_at = Vector2(p)
					worst[i].hidden_facing = Vector2.DOWN.rotated(TAU * f / masks.size())
			for i in on_top:
				if on_top[i] > worst[i].on_top:
					worst[i].on_top = on_top[i]
					worst[i].on_top_at = Vector2(p)
					worst[i].on_top_facing = Vector2.DOWN.rotated(TAU * f / masks.size())
	return worst


## For each facing (as in body_masks): the spots in `reach` where the body's
## real collision shape, turned that way (it turns with the picture), would
## hit something. A body can't face that way there, so it's never drawn so.
func blocked_by_facing(who: Node2D, reach: Dictionary) -> Array:
	var out := []
	var hd = who.get_node_or_null("HdBody")
	var shape_node: CollisionShape2D = who.get_node("CollisionShape2D")
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape_node.shape
	q.collision_mask = who.collision_mask & ~16
	q.exclude = [who.get_rid()]
	var space: PhysicsDirectSpaceState2D = who.get_world_2d().direct_space_state
	var keep_rotation: float = shape_node.rotation
	var keep_position: Vector2 = shape_node.position
	for f in FACINGS:
		var blocked := {}
		if hd and hd.has_method("face"):
			hd.face(Vector2.DOWN.rotated(TAU * f / FACINGS))
		var local := shape_node.transform
		for p in reach:
			q.transform = Transform2D(0.0, Vector2(p)) * local
			if not space.intersect_shape(q, 1).is_empty():
				blocked[p] = true
		out.append(blocked)
	shape_node.rotation = keep_rotation
	shape_node.position = keep_position
	if hd and hd.has_method("face"):
		hd.face(Vector2.DOWN)
	return out


## 1 for every pixel within `radius` of a non-zero pixel of `grid`.
func dilate(grid: PackedByteArray, size: Vector2i, radius: int) -> PackedByteArray:
	var rows := PackedByteArray()
	rows.resize(grid.size())
	for y in size.y:
		var last := -100000
		for x in size.x:   # left to right, then right to left
			if grid[y * size.x + x]:
				last = x
			if x - last <= radius:
				rows[y * size.x + x] = 1
		last = 100000
		for x in range(size.x - 1, -1, -1):
			if grid[y * size.x + x]:
				last = x
			if last - x <= radius:
				rows[y * size.x + x] = 1
	var out := PackedByteArray()
	out.resize(grid.size())
	for x in size.x:
		var last := -100000
		for y in size.y:
			if rows[y * size.x + x]:
				last = y
			if y - last <= radius:
				out[y * size.x + x] = 1
		last = 100000
		for y in range(size.y - 1, -1, -1):
			if rows[y * size.x + x]:
				last = y
			if last - y <= radius:
				out[y * size.x + x] = 1
	return out


## Sweeps a body over every spot it can reach and fails if, in some pose and
## direction, more than WALL_LIMIT of its pixels land on a wall or outside.
## Walls are drawn over the characters, so for a quick attack (`attack`) a
## blade or barrel tucked behind a wall is only a warning; what fails is a
## pixel that comes out on the far side of the wall (it shows through).
func check_walls(label: String, who: Node2D, reach: Dictionary, masks: Array, wall: PackedByteArray, near_wall: PackedByteArray, size: Vector2i, map: Node2D, path: String, rendering: bool, blocked: Array = [], attack := false) -> void:
	var worst := 0
	var worst_at := Vector2.ZERO
	var worst_facing := Vector2.DOWN
	var through_worst := 0
	var through_at := Vector2.ZERO
	var through_facing := Vector2.DOWN
	var spots := 0
	var pool_worst := 0
	var seen := {}   # wall tile -> true, to count places, not pixels
	for p in reach:
		if not near_wall[p.y * size.x + p.x]:
			continue
		for f in masks.size():
			if not blocked.is_empty() and blocked[f].has(p):
				continue
			var n := 0
			var n_pool := 0
			for m in masks[f]:
				var q: Vector2i = p + m
				if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y:
					n += 1
					continue
				var w := wall[q.y * size.x + q.x]
				if w == 1:
					n += 1
				elif w == 2:
					n_pool += 1
			pool_worst = maxi(pool_worst, n_pool)
			if n > WALL_LIMIT:
				seen[Vector2i(p) / int(map.tile_px * 4)] = true
				if attack:
					var through := through_wall(p, masks[f], wall, size)
					if through > through_worst:
						through_worst = through
						through_at = Vector2(p)
						through_facing = Vector2.DOWN.rotated(TAU * f / masks.size())
			if n > worst:
				worst = n
				worst_at = Vector2(p)
				worst_facing = Vector2.DOWN.rotated(TAU * f / masks.size())
	spots = seen.size()
	if attack:
		check(worst <= WALL_LIMIT, "%s is cut off by a wall only briefly (the wall is drawn over it; worst: %d px at %s facing %s, in about %d places)" % [label, worst, worst_at, compass(worst_facing), spots], true)
		check(through_worst <= WALL_LIMIT, "%s never pokes through to the far side of a wall (worst: %d px at %s facing %s)" % [label, through_worst, through_at, compass(through_facing)])
	else:
		check(worst <= WALL_LIMIT, "%s is never drawn into a wall, in any pose or direction (worst: %d px at %s facing %s, in about %d places)" % [label, worst, worst_at, compass(worst_facing), spots])
	check(pool_worst <= WALL_LIMIT, "%s is never drawn over the pool (worst %d px)" % [label, pool_worst], true)
	if rendering and (through_worst > WALL_LIMIT or (worst > WALL_LIMIT and not attack)):
		var at := through_at if attack else worst_at
		var facing := through_facing if attack else worst_facing
		await snapshot(null, who, at, facing, "%s_%s_into_wall" % [path.get_file().get_basename(), label.replace(" ", "_")])


## How many of the body's pixels at `p` sit on open floor with a wall between
## them and the body's centre: the bit that shows on the other side.
func through_wall(p: Vector2i, mask: Array, wall: PackedByteArray, size: Vector2i) -> int:
	var n := 0
	for m in mask:
		var q: Vector2i = p + m
		if q.x < 0 or q.y < 0 or q.x >= size.x or q.y >= size.y or wall[q.y * size.x + q.x] == 1:
			continue
		var steps := maxi(absi(m.x), absi(m.y))
		for k in range(1, steps):
			var r := Vector2i((Vector2(p) + Vector2(m) * k / steps).round())
			if wall[r.y * size.x + r.x] == 1:
				n += 1
				break
	return n


## Puts the player at `at`, renders, and saves a close-up.
func snapshot(level: Node, player: Node2D, at: Vector2, facing: Vector2, label: String) -> void:
	player.global_position = at
	player.get_node("HdBody").face(facing)
	# The camera follows the player; for a dog, hold it still over the dog.
	var camera := player.get_viewport().get_camera_2d()
	var hold: bool = camera != null and player.is_in_group("enemies")
	if hold:
		camera.process_mode = Node.PROCESS_MODE_DISABLED
		camera.global_position = at
		camera.reset_smoothing()
	for i in 30:   # let the camera catch up
		await process_frame
	if hold:
		camera.process_mode = Node.PROCESS_MODE_INHERIT
	var image := root.get_viewport().get_texture().get_image()
	# A close-up around the person, wherever the camera is.
	var stretch := Vector2(image.get_size()) / root.get_viewport().get_visible_rect().size
	var on_screen := Vector2i((player.get_global_transform_with_canvas().origin * stretch).round())
	var box := Rect2i(on_screen - Vector2i(160, 120), Vector2i(320, 240)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image = image.get_region(box)
	var path := "%s/%s.png" % [shots_dir, label.to_snake_case()]
	image.save_png(path)
	note("picture: " + ProjectSettings.globalize_path(path))

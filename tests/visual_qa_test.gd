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
## Real-life sizes seen from above, in metres: [long side min, max, short side min, max].
## The first key found in a piece's name wins, so longer names go first.
const SIZES := {
	"plant": [0.3, 1.0, 0.3, 1.0],   # before "bed": plant_bedroom_l is a plant
	"statue": [0.4, 1.2, 0.4, 1.2],
	"lamp": [0.3, 0.8, 0.3, 0.8],
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
	"dog_bed": [0.6, 1.2, 0.5, 1.0],
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
	var player_radius: float = player.get_node("CollisionShape2D").shape.radius
	var reach := flood(player, player.global_position, player_radius, player.collision_mask & ~16, size)
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
		var worst := sweep(reach, person_masks, owner_of, size, pieces, people_on_top)
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
			var dog_reach := flood(dogs[0], dogs[0].global_position, dogs[0].get_node("CollisionShape2D").shape.radius, 1 | 32, size)
			var dog_worst := sweep(dog_reach, dog_masks, owner_of, size, pieces)
			var dog_bad := range(pieces.size()).filter(func(i): return dog_worst[i].hidden > HIDDEN_LIMIT)
			# Allowed: dogs are shorter than a table (Fianso). Listed for a human look.
			note("dogs can go under (allowed): %s" % [", ".join(dog_bad.map(func(i): return names[i]))])
		if rendering:
			for i in hidden_bad:
				await snapshot(level, player, worst[i].hidden_at, worst[i].hidden_facing, "%s_under_%s" % [path.get_file().get_basename(), names[i]])
			for i in on_top_bad:
				await snapshot(level, player, worst[i].on_top_at, worst[i].on_top_facing, "%s_over_%s" % [path.get_file().get_basename(), names[i]])

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
			var p := Vector2i((xf * (corner + Vector2(x, y) + Vector2(0.5, 0.5))).floor())
			var inside := p.x >= 0 and p.y >= 0 and p.x < size.x and p.y < size.y
			var is_floor := false
			if inside and base_floor and p.x < base_floor.get_width() and p.y < base_floor.get_height():
				var under := base_floor.get_pixelv(p)
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
func sweep(reach: Dictionary, masks: Array, owner_of: PackedInt32Array, size: Vector2i, pieces: Array, on_top_always := false) -> Array:
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


## Puts the player at `at`, renders, and saves a close-up.
func snapshot(level: Node, player: Node2D, at: Vector2, facing: Vector2, label: String) -> void:
	player.global_position = at
	player.get_node("HdBody").face(facing)
	for i in 30:   # let the camera catch up
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	# A close-up around the person, wherever the camera is.
	var stretch := Vector2(image.get_size()) / root.get_viewport().get_visible_rect().size
	var on_screen := Vector2i((player.get_global_transform_with_canvas().origin * stretch).round())
	var box := Rect2i(on_screen - Vector2i(160, 120), Vector2i(320, 240)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	image = image.get_region(box)
	var path := "%s/%s.png" % [shots_dir, label.to_snake_case()]
	image.save_png(path)
	note("picture: " + ProjectSettings.globalize_path(path))

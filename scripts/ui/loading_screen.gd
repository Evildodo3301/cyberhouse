class_name LoadingScreen
extends CanvasLayer
## Between two floors of a level: a full-screen picture (the hero going up
## the stairs) while the next floor loads, then it fades away over the new
## floor. Made by Game.take_stairs(); it lives on the Game autoload so it
## stays up while the scene changes underneath it.

## The picture stays up at least this long, even if the floor loads faster.
@export var min_time: float = 1.8
@export var fade_time: float = 0.4

var _path: String = ""
var _time: float = 0.0
var _arrived: bool = false
var _cover: Control   # everything on the screen, faded out at the end


## Show `picture` (null = a plain stand-in until the real one exists) and
## load the scene at `path`.
func go(path: String, picture: Texture2D) -> void:
	_path = path
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_cover = Control.new()
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cover)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.add_child(black)
	if picture:
		var shown := TextureRect.new()
		shown.name = "Picture"
		shown.texture = picture
		shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shown.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shown.set_anchors_preset(Control.PRESET_FULL_RECT)
		shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cover.add_child(shown)
	else:
		var label := Label.new()
		label.name = "StandIn"
		label.text = "UP THE STAIRS..."
		label.add_theme_font_size_override("font_size", 24)
		label.add_theme_color_override("font_color", Color(0.16, 0.94, 1.0))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_cover.add_child(label)
	ResourceLoader.load_threaded_request(_path)


func _process(delta: float) -> void:
	_time += delta
	if _arrived:
		_cover.modulate.a = 1.0 - _time / fade_time
		if _time >= fade_time:
			queue_free()
		return
	var status := ResourceLoader.load_threaded_get_status(_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS or _time < min_time:
		return
	# Loaded (or the threaded load failed: load it the plain way instead).
	var scene: PackedScene = ResourceLoader.load_threaded_get(_path) if status == ResourceLoader.THREAD_LOAD_LOADED else load(_path)
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().change_scene_to_packed(scene)
	_arrived = true
	_time = 0.0

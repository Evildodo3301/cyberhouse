class_name ScoreBoard
extends CanvasLayer
## Score for the level.
## - Each kill pops "+400" above the body; the number floats up and fades.
## - Kills less than `combo_window` seconds apart chain into a combo: the
##   2nd kill is worth 2x, the 3rd 3x... A "x3 COMBO" counter on the right
##   shows the chain, with a bar that runs down until it breaks.
## - The total sits in the top-right corner.

@export var points_per_kill: int = 400
@export var combo_window: float = 3.0
@export var popup_time: float = 0.8
## How far popups float up (screen px).
@export var popup_rise: float = 22.0
@export var popup_color: Color = Color(1.0, 0.16, 0.55)
@export var combo_color: Color = Color(0.16, 0.94, 1.0)

var score: int = 0
var combo: int = 0
var _combo_left: float = 0.0
var _total: Label
var _combo_label: Label
var _combo_bar: ColorRect
## Each popup: [label, world position, seconds alive].
var _popups: Array = []


func _ready() -> void:
	layer = 5
	_total = _make_label(16, Color(1, 1, 1, 0.9))
	_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_label = _make_label(22, combo_color)
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_combo_bar = ColorRect.new()
	_combo_bar.color = combo_color
	_combo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_combo_bar)
	Game.enemy_died.connect(_on_kill)
	# Arrived from the floor below: carry on from where you were.
	score = Game.carried.get("score", 0)
	combo = Game.carried.get("combo", 0)
	_combo_left = Game.carried.get("combo_left", 0.0)
	_refresh()


func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.0, 0.08))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _on_kill(enemy: Node2D) -> void:
	combo = combo + 1 if _combo_left > 0.0 else 1
	_combo_left = combo_window
	var points := points_per_kill * combo
	score += points
	var label := _make_label(16 if combo < 3 else 20, popup_color)
	label.text = "+%d" % points
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(80, 20)
	_popups.append([label, enemy.global_position, 0.0])
	_refresh()


func _refresh() -> void:
	var width := get_viewport().get_visible_rect().size.x
	_total.text = str(score)
	_total.size = Vector2(160, 20)
	_total.position = Vector2(width - 172, 8)
	_combo_label.visible = combo >= 2
	_combo_label.text = "x%d COMBO" % combo
	_combo_label.size = Vector2(160, 28)
	_combo_label.position = Vector2(width - 172, 30)
	_combo_bar.visible = _combo_label.visible
	var bar := 90.0 * _combo_left / combo_window
	_combo_bar.size = Vector2(bar, 2)
	_combo_bar.position = Vector2(width - 12 - bar, 60)


func _process(delta: float) -> void:
	if _combo_left > 0.0:
		_combo_left = maxf(_combo_left - delta, 0.0)
		if _combo_left == 0.0:
			combo = 0
		_refresh()
	# Popups follow the body on screen (the camera moves and tilts), float up and fade.
	var to_screen := get_viewport().get_canvas_transform()
	for popup in _popups.duplicate():
		var label: Label = popup[0]
		popup[2] += delta
		var t: float = popup[2] / popup_time
		if t >= 1.0:
			label.queue_free()
			_popups.erase(popup)
			continue
		var pop := 1.0 + 0.4 * maxf(1.0 - t * 6.0, 0.0)   # starts big, snaps to size
		label.scale = Vector2(pop, pop)
		label.pivot_offset = label.size / 2.0
		label.position = to_screen * popup[1] - label.size / 2.0 - Vector2(0, 14 + popup_rise * t)
		label.modulate.a = 1.0 if t < 0.6 else (1.0 - t) / 0.4

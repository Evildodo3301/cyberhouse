class_name VoidFlash
extends Node
## Each gunshot tints the empty void outside the map with a neon colour that
## fades in about a fifth of a second. Every shot moves a little further
## round the colour wheel (pink, purple, blue, cyan...), so rapid fire glides
## through colours instead of strobing.

## How fast the flash fades (per second).
@export var fade_speed: float = 5.0
## Highest the flash can build up to, even during rapid fire.
@export var max_strength: float = 0.5
## How far round the colour wheel each shot moves (1 = a full turn).
@export var hue_step: float = 0.09

var strength: float = 0.0
var hue: float = 0.85   # starts on neon pink
var _base: Color


func _ready() -> void:
	_base = ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color")
	Game.shot_fired.connect(_on_shot)


func _exit_tree() -> void:
	RenderingServer.set_default_clear_color(_base)


func _on_shot(weapon: WeaponData) -> void:
	if weapon.void_flash <= 0.0:
		return
	hue = fposmod(hue + hue_step, 1.0)
	strength = minf(maxf(strength, weapon.void_flash), max_strength)


func current_color() -> Color:
	return _base.lerp(Color.from_hsv(hue, 0.9, 1.0), strength)


func _process(delta: float) -> void:
	if strength <= 0.0:
		return
	strength = maxf(strength - fade_speed * strength * delta - 0.2 * delta, 0.0)
	RenderingServer.set_default_clear_color(current_color())

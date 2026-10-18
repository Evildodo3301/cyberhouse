class_name ScreenUnits
## Converts real-world centimetres into game pixels, so on-screen controls
## are the same physical size under your thumb on a phone and on a tablet.

## Game pixels per centimetre of real screen, for the given viewport.
static func per_cm(viewport: Viewport) -> float:
	var dpi := float(DisplayServer.screen_get_dpi())
	if dpi <= 0.0:
		dpi = 160.0
	var window_width := float(DisplayServer.window_get_size().x)
	var game_width := viewport.get_visible_rect().size.x
	if window_width <= 0.0:
		return 20.0
	# screen pixels per cm, then screen pixels -> game pixels
	return (dpi / 2.54) * (game_width / window_width)


## `cm` converted to game pixels, kept between `min_px` and `max_px` so a
## wrong DPI report (some devices lie) can't make controls tiny or huge.
static func cm(viewport: Viewport, centimetres: float, min_px: float, max_px: float) -> float:
	return clampf(centimetres * per_cm(viewport), min_px, max_px)

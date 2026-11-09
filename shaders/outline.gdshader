shader_type canvas_item;
// A thin dark outline around a sprite, so characters stay readable on top
// of blood and busy floors.

uniform vec4 outline_color : source_color = vec4(0.04, 0.0, 0.08, 1.0);
uniform float width = 1.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (color.a < 0.5) {
		vec2 step_size = TEXTURE_PIXEL_SIZE * width;
		// Count only solid neighbours: painted sheets keep faint alpha
		// specks in their empty areas.
		float around = step(0.5, texture(TEXTURE, UV + vec2(step_size.x, 0.0)).a)
			+ step(0.5, texture(TEXTURE, UV - vec2(step_size.x, 0.0)).a)
			+ step(0.5, texture(TEXTURE, UV + vec2(0.0, step_size.y)).a)
			+ step(0.5, texture(TEXTURE, UV - vec2(0.0, step_size.y)).a);
		if (around > 0.0) {
			color = outline_color;
		}
	}
	COLOR = color;
}

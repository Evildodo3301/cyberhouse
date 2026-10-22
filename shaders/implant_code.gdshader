shader_type canvas_item;
// The suit enemy's neural implant: streams of green glyphs running down the
// dark suit, like code, and a faint green cast on the suit itself. Only the
// suit's dark pixels get it; skin, shades and the white collar don't.
// Glyph art: assets/characters/hd/implant_glyphs.png (10 glyphs of 4x6 px,
// 4 rows: head, bright, mid, tail greens). Drawn at game pixels, so the
// glyphs stay crisp whatever the sheet's resolution.

uniform sampler2D glyphs : filter_nearest;
// Game pixels per sheet pixel (the animation's game_scale).
uniform float game_scale = 0.459;
// How dark a pixel has to be to count as suit.
uniform float suit_darkness = 0.16;
// How strongly the glyphs show over the suit.
uniform float glyph_strength = 0.75;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	float luma = dot(color.rgb, vec3(0.3, 0.59, 0.11));
	if (color.a > 0.5 && luma < suit_darkness) {
		color.rgb = color.rgb * 0.8 + vec3(4.0, 22.0, 6.0) / 255.0;
		// Game-pixel position in the sheet; one stream every 4 px.
		vec2 p = floor(UV / TEXTURE_PIXEL_SIZE * game_scale);
		float column = floor(p.x / 4.0);
		float speed = 12.0 + 12.0 * hash(vec2(column, 1.0));   // 1-2 px a tick at 12 ticks/s
		float period = 48.0 + floor(48.0 * hash(vec2(column, 2.0)));
		// About half the columns run at a time, taking turns.
		bool running = hash(vec2(column, floor(TIME * 0.5 + hash(vec2(column, 4.0))))) < 0.5;
		float head = mod(floor(TIME * 12.0) * speed / 12.0 + period * hash(vec2(column, 3.0)), period);
		float behind = floor((head - p.y) / 6.0);   // 0 = head glyph, 1-3 = fading tail
		if (running && behind >= 0.0 && behind < 4.0) {
			float tick = floor(TIME * 4.0);   // glyphs swap every 3 ticks
			float glyph = floor(10.0 * hash(vec2(column, floor(p.y / 6.0) + tick)));
			vec2 inside = vec2(mod(p.x, 4.0), mod(p.y, 6.0));
			vec4 g = texture(glyphs, (vec2(glyph * 4.0, behind * 6.0) + inside + 0.5) / vec2(40.0, 24.0));
			color.rgb = mix(color.rgb, g.rgb, g.a * glyph_strength);
		}
	}
	COLOR = color;
}

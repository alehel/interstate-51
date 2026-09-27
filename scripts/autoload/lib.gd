extends Node
## Shared procedural resources: textures, materials, shaders, and the cached world.

var tex: Dictionary = {}
var mats: Dictionary = {}
var world: WorldData = null     # generated once per session
var fonts: Dictionary = {}

const PARTICLE_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, cull_disabled, BLEND_MODE;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform float soft = 1.0;
varying float v_frame;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	float r = INSTANCE_CUSTOM.y;
	vec2 p = VERTEX.xy;
	p = vec2(p.x * cos(r) - p.y * sin(r), p.x * sin(r) + p.y * cos(r));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX = vec3(p * s, 0.0);
	v_frame = INSTANCE_CUSTOM.x;
}
void fragment() {
	float f = floor(v_frame + 0.5);
	vec2 cell = vec2(mod(f, 4.0), floor(f / 4.0));
	vec4 t = texture(atlas, (cell + UV) * 0.25);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a * COLOR.a;
}
"""

const TRACER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(axis, cam - origin)) * w;
	vec3 world = origin + axis * (VERTEX.y + 0.5) + side * VERTEX.x;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}
void fragment() {
	float edge = 1.0 - abs(UV.x - 0.5) * 2.0;
	float along = smoothstep(0.0, 0.35, 1.0 - UV.y) * smoothstep(0.0, 0.1, UV.y);
	ALBEDO = COLOR.rgb * 2.0;
	ALPHA = COLOR.a * edge * edge * along;
}
"""

const SKY_SHADER := """
shader_type sky;
uniform vec3 top_color : source_color = vec3(0.25, 0.45, 0.8);
uniform vec3 horizon_color : source_color = vec3(0.8, 0.75, 0.65);
uniform vec3 ground_color : source_color = vec3(0.45, 0.38, 0.3);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.9, 0.7);
uniform float sun_size = 0.9995;
uniform float sun_glow = 0.35;
uniform float horizon_power = 0.45;
uniform float stars = 0.0;
uniform sampler2D cloud_tex : repeat_enable, filter_linear_mipmap;
uniform float cloud_amount = 0.5;
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.7, 0.7, 0.75);
uniform vec3 moon_dir = vec3(0.3, 0.6, -0.7);
uniform float moon = 0.0;
uniform float flash = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 col;
	if (h >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(h, 0.0, 1.0), horizon_power));
	} else {
		col = mix(horizon_color, ground_color, clamp(-h * 6.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float sd = dot(d, LIGHT0_DIRECTION);
		float glow = pow(max(sd, 0.0), 6.0) * sun_glow + pow(max(sd, 0.0), 64.0) * sun_glow;
		col += sun_tint * glow;
		col = mix(col, sun_tint * 3.0, smoothstep(sun_size, sun_size + 0.0003, sd));
	}
	if (stars > 0.0 && h > 0.0) {
		vec3 q = floor(d * 380.0);
		float s = hash(q);
		float tw = hash(q + 7.0);
		col += vec3(0.9, 0.95, 1.0) * step(0.9975, s) * stars * (0.4 + tw) * smoothstep(0.0, 0.25, h);
	}
	if (moon > 0.0) {
		float md = dot(d, normalize(moon_dir));
		col += vec3(0.95, 0.95, 0.85) * smoothstep(0.9993, 0.9995, md) * moon * 1.5;
		col += vec3(0.3, 0.35, 0.5) * pow(max(md, 0.0), 40.0) * moon * 0.3;
	}
	if (h > 0.0 && cloud_amount > 0.0) {
		vec2 uv = d.xz / (h + 0.12) * 0.18;
		float c = texture(cloud_tex, uv).r;
		float c2 = texture(cloud_tex, uv * 2.3 + vec2(0.3, 0.7)).r;
		float dens = smoothstep(1.0 - cloud_amount, 1.0, c * 0.7 + c2 * 0.3);
		vec3 cc = mix(cloud_color, cloud_shadow, clamp(c2 * 1.2 - 0.2, 0.0, 1.0));
		col = mix(col, cc, dens * smoothstep(0.0, 0.12, h) * 0.9);
	}
	col += vec3(1.0, 0.95, 0.9) * flash;
	COLOR = col;
}
"""

const BEACON_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
void fragment() {
	float fade = pow(1.0 - UV.y, 1.5) * (0.6 + 0.4 * sin(TIME * 4.0 - UV.y * 20.0));
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 1.5);
	ALBEDO = color.rgb;
	ALPHA = color.a * fade * (0.25 + rim * 0.75);
}
"""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_make_fonts()
	_make_textures()
	_make_materials()

# ------------------------------------------------------------------ fonts

func _make_fonts() -> void:
	for n in ["Rye-Regular", "SpecialElite-Regular", "BebasNeue-Regular"]:
		var path := "res://assets/fonts/%s.ttf" % n
		if ResourceLoader.exists(path):
			fonts[n.split("-")[0].to_lower()] = load(path)
	if not fonts.has("rye"):
		fonts["rye"] = ThemeDB.fallback_font
	if not fonts.has("specialelite"):
		fonts["specialelite"] = ThemeDB.fallback_font
	if not fonts.has("bebasneue"):
		fonts["bebasneue"] = ThemeDB.fallback_font

func font(n: String) -> Font:
	return fonts.get(n, ThemeDB.fallback_font)

# --------------------------------------------------------------- textures

func _noise(seed: int, freq: float, octaves: int = 4, type := FastNoiseLite.TYPE_SIMPLEX_SMOOTH) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.noise_type = type
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	return n

func _img_from_noise(n: FastNoiseLite, w: int, h: int) -> Image:
	var img := n.get_seamless_image(w, h, false, false, 0.1)
	img.convert(Image.FORMAT_RGBA8)
	return img

func _finish(img: Image, repeat := true) -> ImageTexture:
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _make_textures() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 51

	# Sand / ground detail: two noise layers, tinted around 1.0.
	var n1 := _img_from_noise(_noise(1, 0.05, 4), 128, 128)
	var n2 := _img_from_noise(_noise(2, 0.25, 2), 128, 128)
	var sand := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var v := 0.78 + n1.get_pixel(x, y).r * 0.14 + n2.get_pixel(x, y).r * 0.1
			if rng.randf() < 0.04:
				v -= 0.12
			sand.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
	tex["sand"] = _finish(sand)

	# Asphalt: 64 across x 256 along. Edge lines + dashed centre line.
	var asp := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	var an := _img_from_noise(_noise(3, 0.2, 3), 64, 256)
	for y in 256:
		for x in 64:
			var g := 0.2 + an.get_pixel(x, y).r * 0.09 + rng.randf() * 0.04
			var c := Color(g, g, g * 1.02)
			var u := x / 64.0
			if (u > 0.05 and u < 0.075) or (u > 0.925 and u < 0.95):
				c = Color(0.78, 0.78, 0.72) * (0.85 + rng.randf() * 0.15)
			if u > 0.48 and u < 0.52 and y < 128:
				c = Color(0.85, 0.66, 0.15) * (0.85 + rng.randf() * 0.15)
			if u < 0.03 or u > 0.97:
				c = c.lerp(Color(0.5, 0.42, 0.32), 0.5)
			asp.set_pixel(x, y, c)
	# cracks / tar snakes
	for i in 30:
		var px := rng.randi_range(4, 60)
		var py := rng.randi_range(0, 255)
		for k in rng.randi_range(6, 20):
			px = clampi(px + rng.randi_range(-1, 1), 0, 63)
			py = (py + 1) % 256
			asp.set_pixel(px, py, Color(0.08, 0.08, 0.08))
	tex["asphalt"] = _finish(asp)

	# Dirt road with tyre ruts.
	var dirt := Image.create(64, 128, false, Image.FORMAT_RGBA8)
	var dn := _img_from_noise(_noise(4, 0.15, 3), 64, 128)
	for y in 128:
		for x in 64:
			var u := x / 64.0
			var v := 0.85 + dn.get_pixel(x, y).r * 0.2
			var rut := exp(-pow((u - 0.3) * 14.0, 2)) + exp(-pow((u - 0.7) * 14.0, 2))
			v -= rut * 0.13
			var edge := smoothstep(0.0, 0.12, u) * smoothstep(1.0, 0.88, u)
			var c := Color(0.62, 0.5, 0.36) * v
			c = c.lerp(Color(0.72, 0.62, 0.48), 1.0 - edge)
			c.a = 1.0
			dirt.set_pixel(x, y, c)
	tex["dirt"] = _finish(dirt)

	# Weathered wood planks.
	var wood := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var wn := _img_from_noise(_noise(5, 0.02, 3), 128, 128)
	for y in 128:
		for x in 128:
			var plank := int(x / 16)
			var tone := 0.85 + fmod(plank * 0.37, 0.3)
			var grain := 0.85 + sin(y * 0.35 + wn.get_pixel(x, y).r * 12.0 + plank) * 0.08
			var c := Color(0.55, 0.42, 0.3) * tone * grain
			if x % 16 == 0:
				c = Color(0.18, 0.13, 0.1)
			c.a = 1.0
			wood.set_pixel(x, y, c)
	tex["wood"] = _finish(wood)

	# Corrugated metal with rust streaks.
	var metal := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var mn := _img_from_noise(_noise(6, 0.04, 4), 128, 128)
	for y in 128:
		for x in 128:
			var cor := 0.82 + sin(x * TAU / 8.0) * 0.12
			var r := mn.get_pixel(x, y).r
			var rust := smoothstep(0.55, 0.8, r + sin(x * 0.3) * 0.05 + y / 400.0)
			var c := Color(0.7, 0.72, 0.72).lerp(Color(0.5, 0.28, 0.15), rust) * cor
			c.a = 1.0
			metal.set_pixel(x, y, c)
	tex["metal"] = _finish(metal)

	# Stucco / adobe.
	var stucco := _img_from_noise(_noise(7, 0.12, 4), 128, 128)
	for y in 128:
		for x in 128:
			var v := 0.82 + stucco.get_pixel(x, y).r * 0.18
			stucco.set_pixel(x, y, Color(v, v, v))
	tex["stucco"] = _finish(stucco)

	# Concrete with form lines.
	var conc := _img_from_noise(_noise(8, 0.08, 4), 128, 128)
	for y in 128:
		for x in 128:
			var v := 0.75 + conc.get_pixel(x, y).r * 0.2
			if y % 32 == 0:
				v *= 0.8
			conc.set_pixel(x, y, Color(v, v, v))
	tex["concrete"] = _finish(conc)

	# Car grime: mostly white with subtle dirt toward the bottom and scratches.
	var grime := _img_from_noise(_noise(9, 0.06, 4), 128, 128)
	for y in 128:
		for x in 128:
			var v := 0.9 + grime.get_pixel(x, y).r * 0.1
			if rng.randf() < 0.01:
				v = 0.7
			grime.set_pixel(x, y, Color(v, v * 0.98, v * 0.95))
	tex["grime"] = _finish(grime)

	# Rust for junkers.
	var rust := _img_from_noise(_noise(10, 0.07, 5), 128, 128)
	for y in 128:
		for x in 128:
			var r := rust.get_pixel(x, y).r
			var c := Color(1, 1, 1).lerp(Color(0.66, 0.42, 0.26), smoothstep(0.58, 0.8, r) * 0.75)
			rust.set_pixel(x, y, c)
	tex["rust"] = _finish(rust)

	# Desert bush billboard (alpha).
	tex["bush"] = _finish(_bush_image(rng))
	# Joshua-tree leaf cluster (spiky star, alpha).
	tex["spikes"] = _finish(_spike_image(rng))
	tex["particles"] = _finish(_particle_atlas(rng))
	tex["blob"] = _finish(_radial(64, 1.6, Color(0, 0, 0, 0.75)))
	tex["flare"] = _finish(_radial(64, 2.5, Color(1, 1, 1, 1)))
	tex["clouds"] = _finish(_img_from_noise(_noise(11, 0.012, 5), 256, 256))
	tex["gravel"] = tex["sand"]

func _radial(sz: int, power: float, col: Color) -> Image:
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz / 2.0 + 0.5, y - sz / 2.0 + 0.5).length() / (sz / 2.0)
			var a := pow(clampf(1.0 - d, 0, 1), power)
			img.set_pixel(x, y, Color(col.r, col.g, col.b, col.a * a))
	return img

func _bush_image(rng: RandomNumberGenerator) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 26:
		var x := 32.0 + rng.randf_range(-3, 3)
		var y := 63.0
		var ang := rng.randf_range(-1.3, 1.3)
		var len := rng.randf_range(20, 44)
		for s in int(len):
			x += sin(ang) * 1.0
			y -= cos(ang) * 1.0
			ang += rng.randf_range(-0.15, 0.15)
			if x < 1 or x > 62 or y < 1 or y > 62:
				break
			img.set_pixel(int(x), int(y), Color(0.3, 0.25, 0.18, 1))
			if s > 8 and rng.randf() < 0.55:
				var lc := Color(0.42, 0.48, 0.28).lerp(Color(0.6, 0.62, 0.42), rng.randf())
				for dx in [-1, 0, 1]:
					for dy in [-1, 0]:
						var px := clampi(int(x) + dx, 0, 63)
						var py := clampi(int(y) + dy, 0, 63)
						img.set_pixel(px, py, lc)
	return img

func _spike_image(rng: RandomNumberGenerator) -> Image:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in 60:
		var ang := rng.randf() * TAU
		var len := rng.randf_range(12, 30)
		for s in int(len):
			var x := 32 + cos(ang) * s
			var y := 32 + sin(ang) * s
			var c := Color(0.35, 0.45, 0.22).lerp(Color(0.55, 0.6, 0.35), float(s) / len)
			img.set_pixel(clampi(int(x), 0, 63), clampi(int(y), 0, 63), c)
	return img

## 4x4 atlas of 64px cells:
## 0 smoke puff, 1 spark, 2 fire, 3 flare, 4 debris, 5 ring, 6 dust, 7 star flash,
## 8 soft round, 9 leaf/paper
func _particle_atlas(rng: RandomNumberGenerator) -> Image:
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pn := _img_from_noise(_noise(12, 0.09, 4), 64, 64)
	for cell in 16:
		var ox := (cell % 4) * 64
		var oy := int(cell / 4) * 64
		for y in 64:
			for x in 64:
				var p := Vector2(x - 31.5, y - 31.5) / 32.0
				var d := p.length()
				var nz := pn.get_pixel(x, y).r
				var c := Color(0, 0, 0, 0)
				match cell:
					0:
						var a := clampf(1.0 - d * (0.8 + nz * 0.6), 0, 1)
						c = Color(1, 1, 1, pow(a, 1.2))
					1:
						var a := clampf(1.0 - absf(p.x) * 6.0, 0, 1) * clampf(1.0 - absf(p.y), 0, 1)
						c = Color(1, 1, 1, a)
					2:
						var a := clampf(1.0 - d * (0.7 + nz * 0.8), 0, 1)
						c = Color(1, 0.8 + a * 0.2, 0.5 + a * 0.5, pow(a, 0.8))
					3:
						var a := pow(clampf(1.0 - d, 0, 1), 3.0)
						c = Color(1, 1, 1, a)
					4:
						var ang := atan2(p.y, p.x)
						var r := 0.55 + sin(ang * 3.0 + 1.0) * 0.2 + cos(ang * 5.0) * 0.1
						c = Color(0.25, 0.22, 0.2, 1.0 if d < r else 0.0)
					5:
						var a := clampf(1.0 - absf(d - 0.8) * 8.0, 0, 1)
						c = Color(1, 1, 1, a)
					6:
						var a := clampf(1.0 - d * (0.9 + nz * 0.9), 0, 1)
						c = Color(1, 1, 1, a * 0.8)
					7:
						var a := pow(clampf(1.0 - d, 0, 1), 2.0) + clampf(1.0 - absf(p.x) * 10.0, 0, 1) * clampf(1.0 - absf(p.y), 0, 1) + clampf(1.0 - absf(p.y) * 10.0, 0, 1) * clampf(1.0 - absf(p.x), 0, 1)
						c = Color(1, 1, 1, clampf(a, 0, 1))
					8:
						var a := pow(clampf(1.0 - d, 0, 1), 1.5)
						c = Color(1, 1, 1, a)
					9:
						c = Color(0.95, 0.93, 0.85, 1.0 if (absf(p.x) < 0.5 and absf(p.y) < 0.7) else 0.0)
				img.set_pixel(ox + x, oy + y, c)
	return img

# -------------------------------------------------------------- materials

func mat(key: String) -> Material:
	if mats.has(key):
		return mats[key]
	# unknown keys fall back to plain vertex-colour material
	var m := _std(null)
	mats[key] = m
	return m

func _std(t: Texture2D, rough: float = 0.9, metal: float = 0.0, per_vertex: bool = true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	if t:
		m.albedo_texture = t
	m.roughness = rough
	m.metallic = metal
	m.metallic_specular = 0.4
	if per_vertex:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

func _make_materials() -> void:
	mats["plain"] = _std(null)
	mats["terrain"] = _std(tex.sand, 1.0)
	mats["terrain"].metallic_specular = 0.1
	mats["asphalt"] = _std(tex.asphalt, 0.85)
	mats["dirt"] = _std(tex.dirt, 1.0)
	mats["wood"] = _std(tex.wood, 0.95)
	mats["metal"] = _std(tex.metal, 0.6, 0.3)
	mats["stucco"] = _std(tex.stucco, 1.0)
	mats["concrete"] = _std(tex.concrete, 1.0)
	mats["rock"] = _std(tex.sand, 1.0)
	mats["paint"] = _std(tex.grime, 0.35, 0.25, false)
	mats["paint"].metallic_specular = 0.7
	mats["rusty"] = _std(tex.rust, 0.9, 0.1)
	mats["chrome"] = _std(null, 0.12, 1.0, false)
	mats["chrome"].metallic_specular = 1.0
	mats["glass"] = _std(null, 0.05, 0.6, false)
	mats["glass"].metallic_specular = 1.0
	mats["rubber"] = _std(null, 0.95)
	mats["burnt"] = _std(tex.rust, 1.0, 0.0)
	mats["burnt"].albedo_color = Color(0.2, 0.18, 0.17)
	var lamp := StandardMaterial3D.new()
	lamp.vertex_color_use_as_albedo = true
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["lamp"] = lamp
	var glow := StandardMaterial3D.new()
	glow.vertex_color_use_as_albedo = true
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.emission_enabled = true
	glow.emission = Color(1, 1, 1)
	glow.emission_energy_multiplier = 1.5
	mats["glow"] = glow
	var foliage := _std(tex.bush, 1.0)
	foliage.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	foliage.alpha_scissor_threshold = 0.5
	foliage.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["bush"] = foliage
	var spikes := _std(tex.spikes, 1.0)
	spikes.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	spikes.alpha_scissor_threshold = 0.4
	spikes.cull_mode = BaseMaterial3D.CULL_DISABLED
	mats["spikes"] = spikes
	var blob := StandardMaterial3D.new()
	blob.albedo_texture = tex.blob
	blob.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.render_priority = -1
	blob.no_depth_test = false
	mats["blob"] = blob
	var oil := StandardMaterial3D.new()
	oil.albedo_color = Color(0.02, 0.02, 0.03, 0.85)
	oil.albedo_texture = tex.flare
	oil.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	oil.roughness = 0.05
	oil.metallic = 0.8
	mats["oil"] = oil
	var ps := Shader.new()
	ps.code = PARTICLE_SHADER.replace("BLEND_MODE", "blend_add")
	mats["fx_add"] = ShaderMaterial.new()
	mats["fx_add"].shader = ps
	mats["fx_add"].set_shader_parameter("atlas", tex.particles)
	var pm := Shader.new()
	pm.code = PARTICLE_SHADER.replace("BLEND_MODE", "blend_mix")
	mats["fx_mix"] = ShaderMaterial.new()
	mats["fx_mix"].shader = pm
	mats["fx_mix"].set_shader_parameter("atlas", tex.particles)
	var ts := Shader.new()
	ts.code = TRACER_SHADER
	mats["tracer"] = ShaderMaterial.new()
	mats["tracer"].shader = ts
	var bs := Shader.new()
	bs.code = BEACON_SHADER
	mats["beacon"] = ShaderMaterial.new()
	mats["beacon"].shader = bs
	var ss := Shader.new()
	ss.code = SKY_SHADER
	mats["sky"] = ShaderMaterial.new()
	mats["sky"].shader = ss
	mats["sky"].set_shader_parameter("cloud_tex", tex.clouds)

var _thread: Thread
var _pending: WorldData
var _map_tex: ImageTexture

func ensure_world() -> WorldData:
	if world == null:
		if _thread:
			_thread.wait_to_finish()
			_thread = null
			world = _pending
		else:
			world = WorldData.new()
			world.generate()
	return world

## Kick off world generation in the background (menus stay responsive).
func start_world_thread() -> void:
	if world or _thread:
		return
	_pending = WorldData.new()
	_thread = Thread.new()
	_thread.start(_pending.generate)

func world_ready() -> bool:
	if world:
		return true
	if _thread and not _thread.is_alive():
		_thread.wait_to_finish()
		_thread = null
		world = _pending
		return true
	return false

## Hill-shaded road map of Nye County for briefings.
func map_texture() -> ImageTexture:
	if _map_tex:
		return _map_tex
	var w := ensure_world()
	var n := 384
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var paper := Color(0.93, 0.87, 0.72)
	for y in n:
		for x in n:
			var wx := -WorldData.HALF + (x + 0.5) / n * WorldData.SIZE
			var wz := -WorldData.HALF + (y + 0.5) / n * WorldData.SIZE
			var h := w.height(wx, wz)
			var hx := w.height(wx + 16.0, wz) - h
			var hz := w.height(wx, wz + 16.0) - h
			var shade := clampf(0.5 - (hx + hz) * 0.03, 0.0, 1.0)
			var c := paper.lerp(Color(0.78, 0.62, 0.45), clampf(h / 260.0, 0, 1) * 0.8)
			c = c * (0.75 + shade * 0.4)
			if w.flat_mask(wx, wz) > 0.5:
				c = c.lerp(Color(0.97, 0.95, 0.9), 0.6)
			# contour lines
			if int(h / 40.0) != int((h + absf(hx) + absf(hz)) / 40.0) and h > 20.0:
				c = c.lerp(Color(0.55, 0.38, 0.25), 0.35)
			c.a = 1.0
			img.set_pixel(x, y, c)
	for r in w.roads.values():
		var col := Color(0.7, 0.12, 0.08) if r.kind == "asphalt" else Color(0.45, 0.32, 0.2)
		for k in range(0, r.pts.size(), 2):
			var q: Vector3 = r.pts[k]
			var px := int((q.x + WorldData.HALF) / WorldData.SIZE * n)
			var py := int((q.z + WorldData.HALF) / WorldData.SIZE * n)
			for dx in [0, 1]:
				for dy in [0, 1]:
					if px + dx >= 0 and px + dx < n and py + dy >= 0 and py + dy < n:
						img.set_pixel(px + dx, py + dy, col)
	_map_tex = ImageTexture.create_from_image(img)
	return _map_tex

static func map_uv(p: Vector2) -> Vector2:
	return (p + Vector2(WorldData.HALF, WorldData.HALF)) / WorldData.SIZE

class_name EnvSetup
## Time-of-day presets: sky, sun/moon, fog, ambient and post settings.

const PRESETS := {
	"noon": {
		"el": 68.0, "az": 150.0, "sun": Color(1.0, 0.96, 0.88), "energy": 1.25,
		"top": Color(0.18, 0.38, 0.75), "hor": Color(0.8, 0.8, 0.78), "ground": Color(0.55, 0.47, 0.38),
		"amb": 0.55, "fog": Color(0.78, 0.76, 0.72), "fog_d": 0.00011, "clouds": 0.28,
		"cloud_col": Color(1, 1, 1), "cloud_sh": Color(0.75, 0.77, 0.82), "stars": 0.0, "lights": false,
		"exposure": 1.0,
	},
	"afternoon": {
		"el": 38.0, "az": 235.0, "sun": Color(1.0, 0.9, 0.75), "energy": 1.2,
		"top": Color(0.2, 0.36, 0.7), "hor": Color(0.86, 0.78, 0.66), "ground": Color(0.55, 0.45, 0.35),
		"amb": 0.5, "fog": Color(0.85, 0.77, 0.66), "fog_d": 0.00012, "clouds": 0.35,
		"cloud_col": Color(1, 0.97, 0.92), "cloud_sh": Color(0.72, 0.7, 0.75), "stars": 0.0, "lights": false,
		"exposure": 1.0,
	},
	"golden": {
		"el": 11.0, "az": 255.0, "sun": Color(1.0, 0.7, 0.42), "energy": 1.15,
		"top": Color(0.2, 0.3, 0.58), "hor": Color(1.0, 0.68, 0.42), "ground": Color(0.5, 0.36, 0.28),
		"amb": 0.45, "fog": Color(0.95, 0.68, 0.46), "fog_d": 0.00014, "clouds": 0.4,
		"cloud_col": Color(1.0, 0.75, 0.5), "cloud_sh": Color(0.55, 0.4, 0.45), "stars": 0.0, "lights": false,
		"exposure": 1.0,
	},
	"dusk": {
		"el": 2.5, "az": 262.0, "sun": Color(1.0, 0.45, 0.25), "energy": 0.85,
		"top": Color(0.08, 0.1, 0.25), "hor": Color(0.95, 0.42, 0.28), "ground": Color(0.25, 0.16, 0.16),
		"amb": 0.4, "fog": Color(0.55, 0.3, 0.3), "fog_d": 0.00016, "clouds": 0.45,
		"cloud_col": Color(1.0, 0.5, 0.35), "cloud_sh": Color(0.3, 0.2, 0.3), "stars": 0.25, "lights": true,
		"exposure": 1.1,
	},
	"night": {
		"el": 38.0, "az": 200.0, "sun": Color(0.5, 0.6, 0.9), "energy": 0.32, "moon": true,
		"top": Color(0.008, 0.012, 0.035), "hor": Color(0.05, 0.06, 0.1), "ground": Color(0.02, 0.02, 0.03),
		"amb": 0.35, "fog": Color(0.04, 0.05, 0.08), "fog_d": 0.00018, "clouds": 0.2,
		"cloud_col": Color(0.12, 0.13, 0.18), "cloud_sh": Color(0.05, 0.05, 0.08), "stars": 1.0, "lights": true,
		"exposure": 1.25,
	},
	"dawn": {
		"el": 4.0, "az": 88.0, "sun": Color(1.0, 0.6, 0.45), "energy": 0.9,
		"top": Color(0.16, 0.22, 0.45), "hor": Color(1.0, 0.62, 0.5), "ground": Color(0.3, 0.22, 0.22),
		"amb": 0.45, "fog": Color(0.7, 0.5, 0.48), "fog_d": 0.00015, "clouds": 0.4,
		"cloud_col": Color(1.0, 0.65, 0.55), "cloud_sh": Color(0.4, 0.35, 0.5), "stars": 0.12, "lights": true,
		"exposure": 1.05,
	},
	"morning": {
		"el": 22.0, "az": 110.0, "sun": Color(1.0, 0.88, 0.72), "energy": 1.15,
		"top": Color(0.22, 0.4, 0.72), "hor": Color(0.9, 0.82, 0.74), "ground": Color(0.5, 0.42, 0.36),
		"amb": 0.5, "fog": Color(0.85, 0.8, 0.75), "fog_d": 0.00012, "clouds": 0.3,
		"cloud_col": Color(1, 0.96, 0.9), "cloud_sh": Color(0.7, 0.72, 0.8), "stars": 0.0, "lights": false,
		"exposure": 1.0,
	},
}

static func sun_dir(el: float, az: float) -> Vector3:
	var e := deg_to_rad(el)
	var a := deg_to_rad(az)
	return Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e)).normalized()

## Builds WorldEnvironment + DirectionalLight3D under parent. Returns {env, light, preset}.
static func build(parent: Node, time: String) -> Dictionary:
	var p: Dictionary = PRESETS.get(time, PRESETS.noon)
	var sky_mat: ShaderMaterial = Lib.mat("sky").duplicate()
	sky_mat.set_shader_parameter("cloud_tex", Lib.tex.clouds)
	sky_mat.set_shader_parameter("top_color", p.top)
	sky_mat.set_shader_parameter("horizon_color", p.hor)
	sky_mat.set_shader_parameter("ground_color", p.ground)
	sky_mat.set_shader_parameter("sun_tint", p.sun if not p.get("moon", false) else Color(0, 0, 0))
	sky_mat.set_shader_parameter("sun_glow", 0.45 if p.el < 15.0 else 0.25)
	sky_mat.set_shader_parameter("stars", p.stars)
	sky_mat.set_shader_parameter("cloud_amount", p.clouds)
	sky_mat.set_shader_parameter("cloud_color", p.cloud_col)
	sky_mat.set_shader_parameter("cloud_shadow", p.cloud_sh)
	var sd := sun_dir(p.el, p.az)
	if p.get("moon", false):
		sky_mat.set_shader_parameter("moon", 1.0)
		sky_mat.set_shader_parameter("moon_dir", sd)
		sky_mat.set_shader_parameter("sun_glow", 0.0)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = p.amb
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = p.exposure
	env.tonemap_white = 6.0
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = p.fog
	env.fog_density = p.fog_d
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.35
	env.glow_enabled = true
	env.glow_intensity = 0.55 if p.lights else 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.06
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var light := DirectionalLight3D.new()
	light.light_color = p.sun
	light.light_energy = p.energy
	light.shadow_enabled = Game.settings.get("shadows", true)
	light.shadow_bias = 0.08
	light.shadow_normal_bias = 1.5
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	light.directional_shadow_max_distance = 160.0
	light.shadow_blur = 1.5
	parent.add_child(light)
	light.look_at_from_position(Vector3.ZERO, -sd, Vector3.UP if absf(sd.y) < 0.95 else Vector3.FORWARD)
	return {"env": env, "light": light, "preset": p, "sky": sky_mat}

module main;
import raylib6::rl;
import std;

const String EARTH_TEXTURE          =  "resources/img/earth_4k_quant.png";
const String STARMAP_TEXTURE        =  "resources/img/starmap.png";
const float EARTH_RADIUS            =  3.0f;
const float CAMERA_SETTLE_THRESHOLD =  0.5f * rl::DEG2RAD;
const float CAMERA_LERP_SPEED       =  10.0f;
const float CAMERA_ZOOM_SPEED       =  10.0f;
const float CAMERA_ANIM_DURATION    =  1.0f;
const float SUN_GEO_ADJUSTMENT      = -15.0f * rl::DEG2RAD; // 1-hour offset adjustment

constdef Ui : inline int
{
	MARGIN      = 20,
	FONT_SIZE   = 20,
	LIST_OFFSET = 55,
	LINE_HEIGHT = 25
}

enum City : int (float lat, float lon, ZString name)
{
	SALA         { 59.9f, 16.5f, "Sala, Sweden" },
	BUENOS_AIRES { -34.6f, -58.4f, "Buenos Aires" },
	TOKYO        { 35.7f, 139.7f, "Tokyo" },
	DELHI        { 28.6f, 77.2f, "Delhi" },
	SHANGHAI     { 31.2f, 121.5f, "Shanghai" },
	SAO_PAULO    { -23.5f, -46.6f, "Sao Paulo" },
	MEXICO       { 19.4f, -99.1f, "Mexico City" },
	CAIRO        { 30.0f, 31.2f, "Cairo" },
	MUMBAI       { 19.1f, 72.9f, "Mumbai" },
}

struct SphericalCoord
{
	float yaw;
	float pitch;
	float radius;
}

struct GlobeCamera
{
	SphericalCoord target;
	SphericalCoord current;
	SphericalCoord start;
	RLCamera3D camera_3d;
	bool dragging;
	float anim_timer;
	Vec2 vel;
}

fn Vec3 spherical_to_vec3(float yaw, float pitch, float radius)
{
	float cos_pitch = math::cos(pitch);
	return radius * (Vec3) { cos_pitch * math::cos(yaw), math::sin(pitch), cos_pitch * math::sin(yaw) };
}

fn void GlobeCamera.init(&self)
{
	*self = {
		.target = { .yaw = math::HALF_PI - (-30.0f * rl::DEG2RAD), .pitch = 20.0f * rl::DEG2RAD, .radius = 12.0f },
		.current = { .yaw = math::HALF_PI - (-30.0f * rl::DEG2RAD), .pitch = 20.0f * rl::DEG2RAD, .radius = 12.0f },
		.camera_3d = { .up = { 0, 1, 0 }, .fovy = 45, .projection = PERSPECTIVE },
		.anim_timer = CAMERA_ANIM_DURATION,
		.vel = { 0, 0 }
	};
}

fn void GlobeCamera.update(&self, float dt)
{
	float wheel = math::sign((int)rl::get_mouse_wheel_move());

	if (wheel)
	{
		self.target.radius = math::clamp(self.target.radius - wheel * self.target.radius * 0.1f, 3.5f, 40.0f);
	}
	self.current.radius += (self.target.radius - self.current.radius) * CAMERA_ZOOM_SPEED * dt;

	if (rl::is_mouse_button_pressed(LEFT))
	{
		RLRay ray = rl::get_screen_to_world_ray(rl::get_mouse_position(), self.camera_3d);
		if (ray.get_collision_sphere({ 0, 0, 0 }, EARTH_RADIUS).hit)
		{
			self.dragging = true;
			self.anim_timer = CAMERA_ANIM_DURATION;
			self.target.yaw = self.current.yaw;
			self.target.pitch = self.current.pitch;
		}
	}

	if (rl::is_mouse_button_released(LEFT))
	{
		self.dragging = false;
	}

	if (self.dragging)
	{
		Vec2 delta            = rl::get_mouse_delta();
		float dist_to_surface = self.current.radius - EARTH_RADIUS;
		float viewport_height = 2.0f * dist_to_surface * math::tan(self.camera_3d.fovy * 0.5f * rl::DEG2RAD);
		float angle_per_pixel = viewport_height / rl::get_screen_height() / EARTH_RADIUS;

		self.vel = { delta.x * angle_per_pixel / math::max(0.1f, math::cos(self.current.pitch)), delta.y * angle_per_pixel };

		self.target.yaw += self.vel.x;
		self.target.pitch = math::clamp(self.target.pitch + self.vel.y, -1.5f, 1.5f);
		self.current.yaw = self.target.yaw;
		self.current.pitch = self.target.pitch;
	}
	else if (self.anim_timer < CAMERA_ANIM_DURATION)
	{
		self.anim_timer += dt;
		float t       = math::min(self.anim_timer / CAMERA_ANIM_DURATION, 1.0f);
		float eased_t = t * t * (3.0f - 2.0f * t);
		self.current.yaw = self.start.yaw + (self.target.yaw - self.start.yaw) * eased_t;
		self.current.pitch = self.start.pitch + (self.target.pitch - self.start.pitch) * eased_t;
		self.current.radius = self.start.radius + (self.target.radius - self.start.radius) * eased_t;
		self.vel = { 0, 0 };
	}
	else
	{
		self.target.yaw += self.vel.x;
		self.target.pitch = math::clamp(self.target.pitch + self.vel.y, -1.5f, 1.5f);
		self.vel *= math::pow(0.8f, dt * 60.0f);

		self.current.yaw += (self.target.yaw - self.current.yaw) * CAMERA_LERP_SPEED * dt;
		self.current.pitch += (self.target.pitch - self.current.pitch) * CAMERA_LERP_SPEED * dt;
	}

	self.camera_3d.position = spherical_to_vec3(self.current.yaw, self.current.pitch, self.current.radius);
}

fn void GlobeCamera.jump_to(&self, City city)
{
	self.start = self.current;
	self.target.pitch = city.lat * rl::DEG2RAD;
	self.target.yaw = math::HALF_PI - (double)(city.lon * rl::DEG2RAD);
	self.target.radius = 5.0f;

	float diff = self.target.yaw - self.start.yaw;
	if (diff > math::PI)
	{
		self.start.yaw += math::TAU;
	}
	else if (diff < -math::PI)
	{
		self.start.yaw -= math::TAU;
	}

	self.anim_timer = 0.0f;
}

struct Pin
{
	float lat;
	float lon;
}

fn void main()
{
	rl::set_config_flags(WINDOW_RESIZABLE | MSAA_4X_HINT);
	rl::init_window(1024, 600, "C3 Earth Explorer");
	defer rl::close_window();
	rl::set_target_fps(60);

	GlobeCamera cam;
	cam.init();

	RLTexture2D tex = rl::load_texture(EARTH_TEXTURE);
	defer rl::unload_texture(tex);
	assert (tex.id , "Failed to load Earth texture");
	tex.set_filter(BILINEAR);

	RLTexture2D star_tex = rl::load_texture(STARMAP_TEXTURE);
	defer rl::unload_texture(star_tex);
	assert (star_tex.id , "Failed to load Star texture");
	star_tex.set_filter(BILINEAR);

	RLShader shader = rl::load_shader_from_memory(EARTH_VERTEX_SHADER, EARTH_FRAGMENT_SHADER);
	defer rl::unload_shader(shader);

	RLModel model = rl::load_model_from_mesh(rl::gen_mesh_sphere(EARTH_RADIUS, 64, 64));
	defer rl::unload_model(model);

	RLModel skybox = rl::load_model_from_mesh(rl::gen_mesh_sphere(100.0f, 64, 64));
	defer rl::unload_model(skybox);

	model.materials[0].shader = shader;
	model.materials[0].maps[RLMaterialMapIndex.ALBEDO].texture = tex;

	skybox.materials[0].shader = shader;
	skybox.materials[0].maps[RLMaterialMapIndex.ALBEDO].texture = star_tex;

	int sun_pos_loc   = shader.get_location("sunPos");
	int is_skybox_loc = shader.get_location("isSkybox");

	List{Pin} pins;
	pins.init(mem);
	defer pins.free();

	double last_sun_update = -1.0;
	Vec3 sun_pos_cache;

	while (!rl::window_should_close())
	{
		foreach (RLKeyboardKey i, city : City::values)
		{
			if (rl::is_key_pressed(RLKeyboardKey.ONE + i))
			{
				cam.jump_to(city);
			}
		}

		float dt = math::min(rl::get_frame_time(), 0.1f);
		cam.update(dt);

		if (rl::get_time() - last_sun_update > 1.0)
		{
			DateTime now    = datetime::from_time_tz(time::now(), 0).date_time;
            // At 12:00 UTC, the sun is roughly at the Prime Meridian (yaw = PI/2)
			float hours_utc = now.hour + now.min / 60.0f + now.sec / 3600.0f;
			// # Dynamic Equation of Time and Declination (Wikipedia Approximation)
			float n         = now.year_day;
		    // D is the day angle in radians
			float d_angle   = 6.24004077f + 0.01720197f * (n - 1.0f);
			// Equation of Time in minutes: Wikipedia formula
			float eot       = -7.659f * math::sin(d_angle) + 9.863f * math::sin(2.0f * d_angle + 3.5932f);
			float eot_hours =  eot / 60.0f;
			float sun_yaw = (float)math::HALF_PI + (hours_utc + eot_hours - 12.0f) * ((float)math::PI / 12.0f) + SUN_GEO_ADJUSTMENT;
			// Declination formula using the same day angle
			float b           = 2.0f * (float)math::PI * (n - 81.0f) / 365.0f;
			float declination = 23.45f * rl::DEG2RAD * math::sin(b);
			sun_pos_cache = { 1000.0f * math::cos(declination) * math::cos(sun_yaw), 1000.0f * math::sin(declination), 1000.0f * math::cos(declination) * math::sin(sun_yaw) };
			last_sun_update = rl::get_time();
		}
		shader.set_value(sun_pos_loc, &sun_pos_cache, VEC3);

		RLRay ray                = rl::get_screen_to_world_ray(rl::get_mouse_position(), cam.camera_3d);
		RLRayCollision collision = ray.get_collision_sphere({ 0, 0, 0 }, EARTH_RADIUS);

		rl::@drawing()
		{
			rl::clear_background(rl::BLACK);

			rl::@mode3d(cam.camera_3d)
			{
				rl::gl_disable_backface_culling();
				int sky_val = 1;
				shader.set_value(is_skybox_loc, &sky_val, INT);
				rl::draw_model(skybox, { 0, 0, 0 }, 1.0f, rl::WHITE);
				rl::gl_enable_backface_culling();

				int earth_val = 0;
				shader.set_value(is_skybox_loc, &earth_val, INT);
				rl::draw_model(model, { 0, 0, 0 }, 1.0f, rl::GRAY);
				foreach (p : pins)
				{
					Vec3 base = spherical_to_vec3((float)math::HALF_PI - (p.lon * rl::DEG2RAD), p.lat * rl::DEG2RAD, EARTH_RADIUS);
					Vec3 head = base * 1.03f;
					rl::draw_cylinder_ex(base, head, 0.01f, 0.01f, 8, rl::WHITE);
					rl::draw_sphere(head, 0.03f, rl::RED);
				}
			};

			if (collision.hit && (cam.dragging || math::abs(cam.target.yaw - cam.current.yaw) < CAMERA_SETTLE_THRESHOLD))
			{
				Vec3 p    = collision.point.normalize();
				float lat = math::asin(p[1]) * 180 / rl::PI;
				float lon = math::atan2(p[0], p[2]) * 180 / rl::PI;
				rl::draw_text(rl::text_format("Lat: %.3f Lon: %.3f", lat, lon), Ui.MARGIN, rl::get_screen_height() - (Ui.MARGIN + 10), Ui.FONT_SIZE, rl::SKYBLUE);
				if (rl::is_mouse_button_pressed(RIGHT))
				{
					pins.push({ lat, lon });
				}
			}

			float ui_fade       = math::clamp((cam.current.radius - 4.5f) / 2.5f, 0.0f, 1.0f);
			char ui_alpha       = (char)(ui_fade * 255);
			RLColor ui_white    = { 255, 255, 255, ui_alpha };
			RLColor ui_raywhite = { 245, 245, 245, ui_alpha };

			rl::draw_text("C3 Earth Explorer (Left Click: Rotate, Right Click: Pin, Wheel: Zoom, 1-9: Cities)", Ui.MARGIN, Ui.MARGIN, Ui.FONT_SIZE, ui_raywhite);
			$foreach $city : City::values:
				rl::draw_text(rl::text_format("%d: %s", $city.ordinal + 1, $city.name), Ui.MARGIN, Ui.LIST_OFFSET + $city.ordinal * Ui.LINE_HEIGHT, Ui.FONT_SIZE, ui_white);
			$endforeach

			// if (false) rl::draw_text(
			// 	rl::text_format("FPS: %d", rl::get_fps()),
			// 	Ui.MARGIN + rl::get_screen_width() - 140,
			// 	rl::get_screen_height() - (Ui.MARGIN + 10),
			// 	Ui.FONT_SIZE,
			// 	rl::SKYBLUE
			// );
		};
	}
}

// //////////////// Shaders

const ZString EARTH_VERTEX_SHADER @if(env::EMSCRIPTEN) = `#version 300 es
precision highp float;
in vec3 vertexPosition;
uniform mat4 mvp;
uniform mat4 matModel;
out vec3 fragPos;
void main() {
    fragPos = (matModel * vec4(vertexPosition, 1.0)).xyz;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`;

const ZString EARTH_FRAGMENT_SHADER @if(env::EMSCRIPTEN) = `#version 300 es
precision highp float;
in vec3 fragPos;
uniform sampler2D texture0;
uniform vec3 sunPos;
uniform int isSkybox;
out vec4 finalColor;
const float PI = radians(180.0);
void main() {
    vec3 p = normalize(fragPos);
    vec2 uv = vec2(0.5 + atan(p.x, p.z) / (2.0 * PI), 0.5 - asin(p.y) / PI);
    vec4 tex = texture(texture0, uv);
    vec3 lightDir = normalize(sunPos);
    if (isSkybox != 0) {
        float angle = dot(p, lightDir);
        float sunEffect = smoothstep(0.9995, 1.0, angle);
        vec3 sunColor = vec3(1.0, 0.96, 0.7) * sunEffect * 1.5;
        finalColor = vec4(tex.rgb + sunColor, 1.0);
        return;
    }
    float diff = max(dot(p, lightDir), 0.05);
    finalColor = vec4(tex.rgb * diff, 1.0);
}
`;

const ZString EARTH_VERTEX_SHADER @if(!env::EMSCRIPTEN) = `#version 330
in vec3 vertexPosition;
uniform mat4 mvp;
uniform mat4 matModel;
out vec3 fragPos;
void main() {
    fragPos = (matModel * vec4(vertexPosition, 1.0)).xyz;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`;

const ZString EARTH_FRAGMENT_SHADER @if(!env::EMSCRIPTEN) = `#version 330
in vec3 fragPos;
uniform sampler2D texture0;
uniform vec3 sunPos;
uniform int isSkybox;
out vec4 finalColor;
const float PI = 3.14159265359;
void main() {
    vec3 p = normalize(fragPos);
    vec2 uv = vec2(0.5 + atan(p.x, p.z) / (2.0 * PI), 0.5 - asin(p.y) / PI);
    vec4 tex = texture(texture0, uv);
    vec3 lightDir = normalize(sunPos);
    if (isSkybox != 0) {
        float angle = dot(p, lightDir);
        float sunEffect = smoothstep(0.9995, 1.0, angle);
        vec3 sunColor = vec3(1.0, 0.96, 0.7) * sunEffect * 1.5;
        finalColor = vec4(tex.rgb + sunColor, 1.0);
        return;
    }
    float diff = max(dot(p, lightDir), 0.2);
    finalColor = vec4(tex.rgb * diff, 1.0);
}
`;

module std::math; // we can even extend stdlib modules
const TAU = math::PI * 2;
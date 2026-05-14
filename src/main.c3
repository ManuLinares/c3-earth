module main;
import raylib6::rl;
import std;

const String EARTH_TEXTURE          = "resources/img/earth_4k_quant.png";
const String STARMAP_TEXTURE        = "resources/img/starmap.png";
const float EARTH_RADIUS            = 3.0f;
const float CAMERA_SETTLE_THRESHOLD = 0.5f * rl::DEG2RAD;
const float CAMERA_LERP_SPEED       = 10.0f;
const float CAMERA_ZOOM_SPEED       = 10.0f;
const float CAMERA_ANIM_DURATION    = 1.0f;

constdef Ui : inline int
{
	MARGIN      = 20,
	FONT_SIZE   = 20,
	LIST_OFFSET = 55,
	LINE_HEIGHT = 25
}

enum City : int (float lat, float lon, ZString name)
{
	STOCKHOLM    { 59.3f, 18.1f, "Stockholm" },
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
		.target = { .yaw = (float)math::PI / 2.0f - (-30.0f * rl::DEG2RAD), .pitch = 20.0f * rl::DEG2RAD, .radius = 12.0f },
		.current = { .yaw = (float)math::PI / 2.0f - (-30.0f * rl::DEG2RAD), .pitch = 20.0f * rl::DEG2RAD, .radius = 12.0f },
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
	self.target.yaw = (float)math::PI / 2.0f - (city.lon * rl::DEG2RAD);
	self.target.radius = 5.0f;

	float diff = self.target.yaw - self.start.yaw;
	if (diff > math::PI)
	{
		self.start.yaw += 2.0f * math::PI;
	}
	else if (diff < -math::PI)
	{
		self.start.yaw -= 2.0f * math::PI;
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
	rl::init_window(1024, 768, "C3 Earth Explorer");
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

	List{Pin} pins;
	pins.init(mem);
	defer pins.free();

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

		RLRay ray                = rl::get_screen_to_world_ray(rl::get_mouse_position(), cam.camera_3d);
		RLRayCollision collision = ray.get_collision_sphere({ 0, 0, 0 }, EARTH_RADIUS);

		rl::@drawing()
		{
			rl::clear_background(rl::BLACK);

			rl::@mode3d(cam.camera_3d)
			{
				rl::gl_disable_backface_culling();
				rl::draw_model(skybox, { 0, 0, 0 }, 1.0f, rl::WHITE);
				rl::gl_enable_backface_culling();

				rl::draw_model(model, { 0, 0, 0 }, 1.0f, rl::GRAY);
				foreach (p : pins)
				{
					Vec3 base = spherical_to_vec3((float)math::PI / 2.0f - (p.lon * rl::DEG2RAD), p.lat * rl::DEG2RAD, EARTH_RADIUS);
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
out vec4 finalColor;
const float PI = radians(180.0);
void main() {
    vec3 p = normalize(fragPos);
    vec2 uv = vec2(0.5 + atan(p.x, p.z) / (2.0 * PI), 0.5 - asin(p.y) / PI);
    finalColor = texture(texture0, uv);
}
`;

const ZString EARTH_VERTEX_SHADER @if(!env::EMSCRIPTEN) = `
#version 330
in vec3 vertexPosition;
uniform mat4 mvp;
uniform mat4 matModel;
out vec3 fragPos;
void main() {
    fragPos = (matModel * vec4(vertexPosition, 1.0)).xyz;
    gl_Position = mvp * vec4(vertexPosition, 1.0);
}
`;

const ZString EARTH_FRAGMENT_SHADER @if(!env::EMSCRIPTEN) = `
#version 330
in vec3 fragPos;
uniform sampler2D texture0;
out vec4 finalColor;
const float PI = 3.14159265359;
void main() {
    vec3 p = normalize(fragPos);
    vec2 uv = vec2(0.5 + atan(p.x, p.z) / (2.0 * PI), 0.5 - asin(p.y) / PI);
    finalColor = texture(texture0, uv);
}
`;

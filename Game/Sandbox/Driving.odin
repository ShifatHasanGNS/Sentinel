package Sandbox

import "../../Engine/Platform"
import World "../../Engine/World"
import "../Catalogue"
import "../Gameplay"
import "../Vehicles"
import "../../Engine/Render"
import "core:fmt"
import "core:math"
import la "core:math/linalg"

CHASE_DISTANCE_MIN_METERS :: 8.0
CHASE_HEIGHT_FRACTION :: 0.8 // Camera pivot height as a fraction of the vehicle's height.
CHASE_CLEARANCE_METERS :: 0.4
RECENTER_IDLE_SECONDS :: 1.2
AIRCRAFT_CHASE_DISTANCE_METERS :: 16.0
RECENTER_RATE :: 1.6 // Radians per second.
RECENTER_SPEED_MIN :: 2.0
METERS_PER_SECOND_TO_KMH :: 3.6

// Every drivable vehicle in the layout, standing where it was placed, with its hull in the collision world.
vehicles_create :: proc(play: ^Play, sandbox: ^Sandbox) {
	placed := make([dynamic]Vehicles.Placed, context.temp_allocator)
	for placement in sandbox.base.layout.placements {
		if Catalogue.Is_Drivable(placement.kind) do append(&placed, Vehicles.Placed{placement.kind, placement.x, placement.z, math.to_radians(placement.yaw_degrees)})
	}
	base_ground := World.Ground{height_at = terrain_height, data = sandbox.terrain}
	play.vehicles = Vehicles.Vehicles_Create(placed[:], base_ground, &play.battle.collision)
	play.vehicle_renderer = Vehicles.Vehicle_Renderer_Create(play.vehicles[:])
}

vehicles_destroy :: proc(play: ^Play) {
	Vehicles.Vehicle_Renderer_Destroy(&play.vehicle_renderer)
	delete(play.vehicles)
}

// Empty vehicles hold still (handbrake) but still settle onto the terrain and keep their hull solid current.
update_vehicles :: proc(sandbox: ^Sandbox, delta_seconds: f32) {
	play := &sandbox.play
	for &vehicle, index in play.vehicles {
		if driven, ok := play.driving.?; ok && driven == index do continue
		Vehicles.Vehicle_Update(&vehicle, {}, &play.battle.collision, play.battle.ground, delta_seconds)
	}
}

// The vehicle the player could climb into from here, the nearest if several.
nearest_boardable :: proc(play: ^Play) -> Maybe(int) {
	position := play.battle.player.controller.position
	best := math.INF_F32
	found: Maybe(int)
	for vehicle, index in play.vehicles {
		if !Vehicles.Vehicle_Can_Board(vehicle, position) do continue
		vehicle_position, _, _, _ := Vehicles.Vehicle_Pose(vehicle)
		if distance := la.length(vehicle_position - position); distance < best do best, found = distance, index
	}
	return found
}

// For checks: starts the player inside the first vehicle whose name matches (case-insensitive).
board_named_vehicle :: proc(play: ^Play, name: string) {
	for vehicle, index in play.vehicles {
		if !Catalogue.Object_Name_Matches(vehicle.kind, name) do continue
		play.boardable = index
		board_vehicle(play)
		sync_player_to_seat(play)
		return
	}
}

@(private = "file")
sync_player_to_seat :: proc(play: ^Play) {
	vehicle := play.vehicles[play.driving.?]
	play.battle.player.controller.position = Vehicles.Vehicle_Seat_Position(vehicle) - {0, Gameplay.PLAYER_EYE_HEIGHT_METERS, 0}
}

board_vehicle :: proc(play: ^Play) {
	index, ok := play.boardable.?
	if !ok do return
	vehicle := &play.vehicles[index]
	vehicle.occupied = true
	play.driving = index
	play.seat_view = false
	play.mouse_idle_seconds = 0
	play.battle.player.armor = 1 - vehicle.spec.armor
	play.battle.player.pitch_radians = -0.2
	_, yaw, _, _ := Vehicles.Vehicle_Pose(vehicle^)
	play.battle.player.yaw_radians = yaw - math.PI
	play.boardable = nil
}

@(private = "file")
leave_vehicle :: proc(sandbox: ^Sandbox) {
	play := &sandbox.play
	vehicle := &play.vehicles[play.driving.?]
	exit := Vehicles.Vehicle_Exit_Position(vehicle^, play.battle.collision, play.battle.ground)
	play.battle.player.controller = World.Controller_Create(exit)
	play.battle.player.armor = 0
	vehicle.occupied = false
	play.driving = nil
	sync_camera_to_player(sandbox)
}

// One frame in the driver's seat: WASD drive, Space brakes, the mouse aims the turret and orbits the camera, the left button fires,
// V swaps chase camera and seat view, E gets out (only when nearly stopped).
drive_vehicle :: proc(sandbox: ^Sandbox, input: ^Platform.Input, exit_pressed: bool, delta_seconds: f32) {
	play := &sandbox.play
	vehicle := &play.vehicles[play.driving.?]
	player := &play.battle.player
	mouse := collect_input(input)
	Gameplay.Battle_Update(&play.battle, Gameplay.Player_Input{look = mouse.look}, delta_seconds)
	play.mouse_idle_seconds = 0 if abs(mouse.look.x) + abs(mouse.look.y) > 1e-4 else play.mouse_idle_seconds + delta_seconds
	view_down := Platform.Input_Key_Down(input, .V)
	if view_down && !play.view_was_down do play.seat_view = !play.seat_view
	play.view_was_down = view_down
	controls := Vehicles.Vehicle_Controls{aim_yaw = player.yaw_radians + math.PI, aim_pitch = player.pitch_radians}
	if vehicle.spec.is_aircraft {
		controls.fly = World.Aircraft_Input{
			collective = key_axis(input, .Space, .Left_Control), pitch = key_axis(input, .W, .S), roll = key_axis(input, .E, .Q), yaw = key_axis(input, .D, .A),
		}
	} else {
		controls.drive = World.Vehicle_Input{throttle = key_axis(input, .W, .S), steer = key_axis(input, .D, .A), brake = Platform.Input_Key_Down(input, .Space)}
		if play.demo do controls.drive = World.Vehicle_Input{throttle = 1, steer = 0.25 * math.sin(play.demo_seconds * 0.8)}
	}
	if play.demo && vehicle.spec.is_aircraft do controls.fly = World.Aircraft_Input{collective = 1 if play.demo_seconds < 8 else 0, pitch = 0.6 if play.demo_seconds > 6 else 0}
	Vehicles.Vehicle_Update(vehicle, controls, &play.battle.collision, play.battle.ground, delta_seconds)
	if vehicle.spec.is_aircraft do apply_hard_landing(play, vehicle.air.impact_speed)
	else {
		handling := vehicle.spec.handling
		Gameplay.Battle_Run_Over(&play.battle, vehicle.body.position, handling.half_width, handling.half_length, vehicle.body.yaw_radians, vehicle.body.speed)
	}
	play.demo_seconds += delta_seconds
	firing := Platform.Input_Mouse_Down(input, .Left) || (play.demo && int(play.demo_seconds * 2) % 3 == 0)
	if firing && Vehicles.Vehicle_Fire(vehicle, &play.battle) do play.recoil = 0
	recenter_camera(play, vehicle^, delta_seconds)
	seat := Vehicles.Vehicle_Seat_Position(vehicle^)
	player.controller.position = seat - {0, Gameplay.PLAYER_EYE_HEIGHT_METERS, 0}
	player.controller.velocity = {}
	sandbox.camera = vehicle_camera(play, vehicle^)
	if exit_pressed && Vehicles.Vehicle_Is_Settled(vehicle^) do leave_vehicle(sandbox)
}

@(private = "file")
key_axis :: proc(input: ^Platform.Input, positive, negative: Platform.Key) -> f32 {
	return f32(int(Platform.Input_Key_Down(input, positive))) - f32(int(Platform.Input_Key_Down(input, negative)))
}

// Without a turret to aim, the camera swings back behind a moving vehicle once the mouse has been still for a moment.
@(private = "file")
recenter_camera :: proc(play: ^Play, vehicle: Vehicles.Vehicle, delta_seconds: f32) {
	if vehicle.spec.weapon != .None || play.mouse_idle_seconds < RECENTER_IDLE_SECONDS || abs(vehicle_speed(vehicle)) < RECENTER_SPEED_MIN do return
	player := &play.battle.player
	_, heading, _, _ := Vehicles.Vehicle_Pose(vehicle)
	behind := heading - math.PI
	player.yaw_radians += clamp(Vehicles.wrap_angle(behind - player.yaw_radians), -RECENTER_RATE * delta_seconds, RECENTER_RATE * delta_seconds)
	player.pitch_radians += clamp(-0.2 - player.pitch_radians, -RECENTER_RATE * delta_seconds, RECENTER_RATE * delta_seconds)
}

// Seat view looks out from the occupant's eye along the aim; chase view sits behind and above, looking the same way, and is pulled
// in so walls and hills never sit between it and the vehicle.
@(private = "file")
vehicle_camera :: proc(play: ^Play, vehicle: Vehicles.Vehicle) -> Fly_Camera {
	player := play.battle.player
	forward := Gameplay.Player_Forward(player)
	if play.seat_view {
		return Fly_Camera{position = Vehicles.Vehicle_Seat_Position(vehicle), yaw_radians = player.yaw_radians, pitch_radians = player.pitch_radians}
	}
	vehicle_position, _, _, _ := Vehicles.Vehicle_Pose(vehicle)
	_, half_length, height, _ := Vehicles.Vehicle_Hull(vehicle)
	pivot := vehicle_position + {0, height * CHASE_HEIGHT_FRACTION, 0}
	distance := max(CHASE_DISTANCE_MIN_METERS, half_length * 2.4)
	if vehicle.spec.is_aircraft do distance = AIRCRAFT_CHASE_DISTANCE_METERS
	collision := play.battle.collision
	own := &play.battle.collision.boxes[vehicle.solid_index]
	own.disabled = true
	hit := World.Raycast_World(collision, play.battle.ground, pivot, -forward, distance)
	own.disabled = false
	if hit.hit do distance = max(hit.distance - CHASE_CLEARANCE_METERS, 1.5)
	position := pivot - forward * distance
	ground_height := play.battle.ground.height_at(play.battle.ground.data, position.x, position.z)
	position.y = max(position.y, ground_height + CHASE_CLEARANCE_METERS + 0.3)
	return Fly_Camera_Looking_At(position, pivot + forward * 20)
}

// Horizontal speed in m/s, signed for ground vehicles (negative is reverse).
@(private = "file")
vehicle_speed :: proc(vehicle: Vehicles.Vehicle) -> f32 {
	if vehicle.spec.is_aircraft do return la.length([2]f32{vehicle.air.velocity.x, vehicle.air.velocity.z})
	return vehicle.body.speed
}

// A helicopter that lands hard hurts its pilot: damage grows with the sink rate above the safe speed.
@(private = "file")
apply_hard_landing :: proc(play: ^Play, impact_speed: f32) {
	if impact_speed <= Vehicles.HARD_LANDING_SPEED do return
	Gameplay.Health_Apply_Damage(&play.battle.player.health, (impact_speed - Vehicles.HARD_LANDING_SPEED) * Vehicles.HARD_LANDING_DAMAGE_PER_SPEED, .Torso)
	play.battle.player.damage_flash = 1
}

// The speed readout and the controls hint, and the gun's or rotor's state, along the bottom of the screen.
draw_vehicle_hud :: proc(play: ^Play, width, height, scale: f32) {
	hud := &play.hud
	vehicle := play.vehicles[play.driving.?]
	speed := fmt.tprintf("%d KM/H", int(abs(vehicle_speed(vehicle)) * METERS_PER_SECOND_TO_KMH))
	hud_text_right(hud, width - 16, height - 16 - 12 * scale * 1.5, speed, scale * 1.5, {1, 0.95, 0.6, 0.95})
	hint := "E EXIT   V VIEW   SPACE BRAKE"
	if vehicle.spec.is_aircraft {
		ground := play.battle.ground.height_at(play.battle.ground.data, vehicle.air.position.x, vehicle.air.position.z)
		status := fmt.tprintf("ALT %d M   ROTOR %d%%", int(vehicle.air.position.y - ground), int(vehicle.air.rotor * 100))
		hud_text_right(hud, width - 16, height - 16 - 24 * scale * 1.5, status, scale, {1, 1, 1, 0.9})
		hint = "SPACE UP  CTRL DOWN  W/S PITCH  A/D TURN  Q/E STRAFE  V VIEW  E EXIT ON GROUND"
	} else if vehicle.spec.weapon == .Cannon {
		status := "CANNON READY" if vehicle.cooldown_seconds <= 0 else "RELOADING"
		hud_text_right(hud, width - 16, height - 16 - 24 * scale * 1.5, status, scale, {1, 1, 1, 0.85})
	}
	hud_text_right(hud, width - 16, height - 16 - 36 * scale * 1.5, hint, scale, {1, 1, 1, 0.6})
}

@(private = "file")
hud_text_right :: proc(hud: ^Render.Hud, right, y: f32, text: string, scale: f32, color: [4]f32) {
	Render.Hud_Text(hud, right - Render.Hud_Text_Width(text, scale), y, text, scale, color)
}

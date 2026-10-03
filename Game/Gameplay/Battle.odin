package Gameplay

import "../../Engine/Procedural"
import World "../../Engine/World"
import "../Characters"
import "../Weapons"
import "core:math"
import la "core:math/linalg"

ROCKET_GRAVITY :: [3]f32{0, -0.6, 0}
GRENADE_GRAVITY :: [3]f32{0, -9.81, 0}
GRENADE_FUSE_SECONDS :: 2.5
GRENADE_RESTITUTION :: 0.35
GRENADE_FRICTION :: 0.6
ROCKET_LIFETIME_SECONDS :: 6.0
HEARING_RANGE_METERS :: 70.0
SHOUT_RADIUS_METERS :: 22.0
BODY_SIGHT_METERS :: 14.0
EFFECT_TRACER_SECONDS :: 0.12
EFFECT_FLASH_SECONDS :: 0.06
EFFECT_IMPACT_SECONDS :: 0.35
EFFECT_EXPLOSION_SECONDS :: 0.6
DEATH_FALL_FREQUENCY :: 5.0
DEATH_LEAN_METERS :: 0.55
SELF_BLAST_FRACTION :: 0.5
RUN_OVER_SPEED_MIN :: 2.5
RUN_OVER_MARGIN :: 0.2
RUN_OVER_DAMAGE_PER_SPEED :: 12.0 // 100 health is gone by about 8 m/s.
ENEMY_HEAD_CHANCE :: 0.08

Shot_Kind :: enum {
	None,
	World,
	Enemy,
	Target,
}

Shot_Result :: struct {
	kind:        Shot_Kind,
	distance:    f32,
	point:       [3]f32,
	normal:      [3]f32,
	enemy_index: int,
	target_index: int,
	zone:        Hit_Zone,
	killed:      bool,
}

// Short-lived visuals the presentation draws and the simulation ages out.
Effect_Kind :: enum {
	Tracer,
	Muzzle_Flash,
	Impact,
	Explosion,
}

Effect :: struct {
	kind:     Effect_Kind,
	position: [3]f32,
	end:      [3]f32,
	age:      f32,
	lifetime: f32,
	silenced: bool, // A suppressed shot: drawn without a flash, heard only faintly.
}

Projectile_Entity :: struct {
	using body: World.Projectile,
	kind:       Weapons.Weapon_Kind,
	age:        f32,
}

// The whole fight: the player, the enemies, what is in flight, and the static world they move through.
Battle :: struct {
	collision:   World.Collision_World,
	ground:      World.Ground,
	player:      Player,
	enemies:     [dynamic]Enemy,
	targets:     [dynamic]Target,
	pickups:     [dynamic]Pickup,
	projectiles: [dynamic]Projectile_Entity,
	effects:     [dynamic]Effect,
	seed:        u32,
	shot_noise_radius: f32, // How far this frame's shot (if any) carries; 0 when the player did not shoot.
}

Battle_Create :: proc(ground: World.Ground, solids: []World.Solid, spawn: [3]f32, seed: u32) -> (battle: Battle) {
	battle.ground = ground
	battle.seed = seed
	battle.player = Player_Create(spawn)
	for solid in solids do append(&battle.collision.boxes, solid)
	return battle
}

Battle_Destroy :: proc(battle: ^Battle) {
	World.Collision_World_Destroy(&battle.collision)
	for &enemy in battle.enemies do Enemy_Destroy(&enemy)
	delete(battle.enemies)
	delete(battle.targets)
	delete(battle.pickups)
	delete(battle.projectiles)
	delete(battle.effects)
}

Battle_Add_Enemy :: proc(battle: ^Battle, variant: Characters.Soldier_Variant, position: [3]f32, heading_radians: f32, waypoints: [][3]f32) -> int {
	append(&battle.enemies, Enemy_Create(variant, position, heading_radians, waypoints, battle.seed + u32(len(battle.enemies)) * 7919))
	return len(battle.enemies) - 1
}

Battle_Update :: proc(battle: ^Battle, input: Player_Input, delta_seconds: f32) {
	battle.shot_noise_radius = 0
	update_player(battle, input, delta_seconds)
	health_before := battle.player.health.current
	for index in 0 ..< len(battle.enemies) do update_enemy(battle, index, delta_seconds)
	regenerate_player(&battle.player, health_before, delta_seconds)
	collect_pickups(battle)
	update_projectiles(battle, delta_seconds)
	update_effects(battle, delta_seconds)
}

Battle_Add_Target :: proc(battle: ^Battle, position: [3]f32, radius, health: f32) -> int {
	append(&battle.targets, Target_Create(position, radius, health))
	return len(battle.targets) - 1
}

// A bullet from anything but the player's own hands (a vehicle's gun): traced, with a flash, a tracer and an impact.
Battle_Fire_Bullet :: proc(battle: ^Battle, origin, direction: [3]f32, damage, range_meters: f32) {
	battle.shot_noise_radius = SHOT_RADIUS_METERS
	result := Resolve_Hitscan(battle, origin, direction, damage, range_meters)
	end := origin + direction * (result.distance if result.kind != .None else range_meters)
	append(&battle.effects, Effect{kind = .Muzzle_Flash, position = origin, lifetime = EFFECT_FLASH_SECONDS})
	append(&battle.effects, Effect{kind = .Tracer, position = origin, end = end, lifetime = EFFECT_TRACER_SECONDS})
	if result.kind != .None do append(&battle.effects, Effect{kind = .Impact, position = result.point, end = result.normal, lifetime = EFFECT_IMPACT_SECONDS})
}

// Everyone within `radius` of `position` who is not already fighting turns toward it (an alarm, a shout).
Battle_Alert_Nearby :: proc(battle: ^Battle, position: [3]f32, radius: f32) {
	for &enemy in battle.enemies {
		if !Enemy_Is_Alive(enemy) do continue
		if la.length(enemy.controller.position - position) <= radius do Enemy_Ai_Notice(&enemy.ai, position)
	}
}

// A rocket or grenade-like shell in flight; it detonates on impact or at the end of its life like the player's.
Battle_Spawn_Projectile :: proc(battle: ^Battle, kind: Weapons.Weapon_Kind, position, velocity: [3]f32) {
	battle.shot_noise_radius = SHOT_RADIUS_METERS
	append(&battle.effects, Effect{kind = .Muzzle_Flash, position = position, lifetime = EFFECT_FLASH_SECONDS})
	append(&battle.projectiles, Projectile_Entity{body = World.Projectile{position, velocity}, kind = kind})
}

// A vehicle at `speed` runs over living enemies inside its footprint (a rectangle turned by `yaw`, as in World.Ground_Vehicle).
Battle_Run_Over :: proc(battle: ^Battle, center: [3]f32, half_width, half_length, yaw, speed: f32) {
	if abs(speed) < RUN_OVER_SPEED_MIN do return
	for index in 0 ..< len(battle.enemies) {
		enemy := battle.enemies[index]
		if !Enemy_Is_Alive(enemy) do continue
		local := World.rotate_about_y(enemy.controller.position - center, -yaw)
		if abs(local.x) < half_width + RUN_OVER_MARGIN && abs(local.z) < half_length + RUN_OVER_MARGIN && abs(local.y) < 2 {
			damage_enemy(battle, index, RUN_OVER_DAMAGE_PER_SPEED * abs(speed), .Torso, center)
		}
	}
}

// What a bullet strikes: the nearest of the world (walls, terrain) and any living enemy's body parts. Applies the damage.
Resolve_Hitscan :: proc(battle: ^Battle, origin, direction: [3]f32, damage, range: f32) -> (result: Shot_Result) {
	world_hit := World.Raycast_World(battle.collision, battle.ground, origin, direction, range)
	nearest := world_hit.distance if world_hit.hit else range
	if world_hit.hit do result = Shot_Result{kind = .World, distance = world_hit.distance, point = world_hit.point, normal = world_hit.normal}
	for &enemy, index in battle.enemies {
		if !Enemy_Is_Alive(enemy) do continue
		distance, zone, hit := Enemy_Raycast(enemy, origin, direction)
		if !hit || distance > nearest do continue
		nearest = distance
		result = Shot_Result{kind = .Enemy, distance = distance, point = origin + direction * distance, enemy_index = index, zone = zone}
	}
	for &target, index in battle.targets {
		if target.destroyed do continue
		hit := World.Ray_Sphere(origin, direction, target.position, target.radius)
		if !hit.hit || hit.distance > nearest do continue
		nearest = hit.distance
		result = Shot_Result{kind = .Target, distance = hit.distance, point = hit.point, normal = hit.normal, target_index = index}
	}
	if result.kind == .Enemy do result.killed = damage_enemy(battle, result.enemy_index, damage, result.zone, origin)
	if result.kind == .Target do result.killed = damage_target(battle, result.target_index, damage)
	return result
}

// Area damage around a point: each living enemy takes the centre damage scaled by Explosion_Falloff from its chest.
Battle_Detonate :: proc(battle: ^Battle, position: [3]f32, radius, damage: f32) {
	append(&battle.effects, Effect{kind = .Explosion, position = position, lifetime = EFFECT_EXPLOSION_SECONDS})
	for index in 0 ..< len(battle.enemies) {
		if !Enemy_Is_Alive(battle.enemies[index]) do continue
		falloff := Weapons.Explosion_Falloff(la.length(Enemy_Chest_Position(battle.enemies[index]) - position), radius)
		if falloff > 0 do damage_enemy(battle, index, damage * falloff, .Torso, position)
	}
	for index in 0 ..< len(battle.targets) {
		falloff := Weapons.Explosion_Falloff(max(la.length(battle.targets[index].position - position) - battle.targets[index].radius, 0), radius)
		if falloff > 0 do damage_target(battle, index, damage * falloff * TARGET_BLAST_MULTIPLIER)
	}
	player_falloff := Weapons.Explosion_Falloff(la.length(Player_Eye(battle.player) - position), radius)
	if player_falloff > 0 && !Health_Is_Dead(battle.player.health) {
		Health_Apply_Damage(&battle.player.health, damage * player_falloff * SELF_BLAST_FRACTION, .Torso)
		battle.player.damage_flash = 1
	}
}

// A hit on a target; its destruction is a big explosion, and the player sees the hit marker.
@(private = "file")
damage_target :: proc(battle: ^Battle, index: int, damage: f32) -> (destroyed: bool) {
	target := &battle.targets[index]
	battle.player.hit_marker = HIT_MARKER_SECONDS
	destroyed = Target_Damage(target, damage)
	if destroyed do append(&battle.effects, Effect{kind = .Explosion, position = target.position, lifetime = EFFECT_EXPLOSION_SECONDS * 2})
	return destroyed
}

@(private = "file")
damage_enemy :: proc(battle: ^Battle, index: int, damage: f32, zone: Hit_Zone, from: [3]f32) -> (killed: bool) {
	enemy := &battle.enemies[index]
	killed = Health_Apply_Damage(&enemy.health, damage, zone)
	battle.player.hit_marker = HIT_MARKER_SECONDS
	if killed {
		Enemy_Ai_Kill(&enemy.ai)
		battle.player.kills += 1
		weapon := Characters.Soldier_Weapon(enemy.character.variant)
		Battle_Add_Pickup(battle, .Ammo, enemy.controller.position + {0.4, 0, 0.3}, weapon)
		Battle_Add_Pickup(battle, .Weapon, enemy.controller.position + {-0.4, 0, 0.2}, weapon) // The soldier's own weapon falls beside him. // The soldier's spare magazines fall beside him.
	} else {
		Enemy_Ai_Notice(&enemy.ai, from)
		Characters.Character_Hit(&enemy.character, la.normalize([3]f32{enemy.controller.position.x - from.x, 0, enemy.controller.position.z - from.z}))
	}
	return killed
}

@(private = "file")
update_player :: proc(battle: ^Battle, input: Player_Input, delta_seconds: f32) {
	player := &battle.player
	player.damage_flash = max(player.damage_flash - DAMAGE_FLASH_DECAY_PER_SECOND * delta_seconds, 0)
	player.hit_marker = max(player.hit_marker - delta_seconds, 0)
	player.pickup_flash = max(player.pickup_flash - delta_seconds, 0)
	if Health_Is_Dead(player.health) {
		if input.respawn do Player_Respawn(player)
		return
	}
	Player_Look(player, input.look)
	if kind, chosen := input.select.?; chosen do player.current = kind
	World.Controller_Set_Crouch(&player.controller, battle.collision, input.crouch)
	wish := Player_Wish_Velocity(player^, input)
	if into_wall, on_ladder := World.Ladder_Near(battle.collision, player.controller.position, World.LADDER_REACH_METERS, player.controller.on_ground); on_ladder {
		wish = into_wall * (input.move.y * WALK_SPEED) // On a ladder forward is up and back is down, however the player is facing.
	}
	World.Controller_Step(&player.controller, battle.collision, battle.ground, wish, input.jump, delta_seconds)
	stats := Weapons.Weapon_Stats_For(player.current)
	if Weapons.Weapon_Update(&player.weapons[player.current], stats, input.fire, input.reload, delta_seconds) do fire_player_weapon(battle, stats)
}

@(private = "file")
fire_player_weapon :: proc(battle: ^Battle, stats: Weapons.Weapon_Stats) {
	player := &battle.player
	player.shots_fired += 1
	battle.shot_noise_radius = SILENCED_SHOT_RADIUS if stats.silenced else SHOT_RADIUS_METERS
	origin, aim := Player_Eye(player^), Player_Forward(player^)
	roll := proc(battle: ^Battle, salt: i32) -> f32 {
		return Procedural.Hash_To_Unit_Float(Procedural.Hash_Lattice_3(i32(battle.player.shots_fired), salt, 31, battle.seed))
	}
	direction := World.Spread_Direction(aim, math.to_radians(stats.spread_degrees), roll(battle, 1), roll(battle, 2))
	muzzle := origin + aim * 0.7
	append(&battle.effects, Effect{kind = .Muzzle_Flash, position = muzzle, lifetime = EFFECT_FLASH_SECONDS, silenced = stats.silenced})
	if stats.muzzle_speed > 0 {
		append(&battle.projectiles, Projectile_Entity{body = World.Projectile{muzzle, direction * stats.muzzle_speed}, kind = player.current})
		return
	}
	result := Resolve_Hitscan(battle, origin, direction, stats.damage, stats.range_meters)
	end := origin + direction * (result.distance if result.kind != .None else stats.range_meters)
	append(&battle.effects, Effect{kind = .Tracer, position = muzzle, end = end, lifetime = EFFECT_TRACER_SECONDS})
	if result.kind != .None do append(&battle.effects, Effect{kind = .Impact, position = result.point, end = result.normal, lifetime = EFFECT_IMPACT_SECONDS})
}

// Out of combat the player heals: a hit this frame restarts the delay, and after it the health climbs steadily.
@(private = "file")
regenerate_player :: proc(player: ^Player, health_before, delta_seconds: f32) {
	if Health_Is_Dead(player.health) do return
	if player.health.current < health_before {
		player.seconds_since_damage = 0
		return
	}
	player.seconds_since_damage += delta_seconds
	if player.seconds_since_damage >= PLAYER_REGEN_DELAY_SECONDS do Health_Heal(&player.health, PLAYER_REGEN_PER_SECOND * delta_seconds)
}

@(private = "file")
update_enemy :: proc(battle: ^Battle, index: int, delta_seconds: f32) {
	enemy := &battle.enemies[index]
	if !Enemy_Is_Alive(enemy^) {
		fall_after_death(enemy, delta_seconds)
		return
	}
	enemy.ai.position = enemy.controller.position
	senses := enemy_senses(battle, enemy^)
	was_unaware := enemy.ai.state == .Patrol || enemy.ai.state == .Search
	output := Enemy_Ai_Update(&enemy.ai, senses, enemy.waypoints[:], delta_seconds)
	if was_unaware && enemy.ai.state == .Alert do shout(battle, index, enemy.ai.last_known) // He has noticed something: his squad hears him.
	if enemy.ai.state == .Patrol do discover_bodies(battle, index)
	wish := [2]f32{output.move_direction.x, output.move_direction.z} * output.speed
	World.Controller_Step(&enemy.controller, battle.collision, battle.ground, wish, false, delta_seconds)
	animate_enemy(enemy, output, wish, battle.player, delta_seconds)
	trigger := output.shoot
	if Weapons.Weapon_Update(&enemy.weapon, Enemy_Weapon_Stats(), trigger, false, delta_seconds) do enemy_fires(battle, index)
}

// A soldier who spots trouble calls out; idle soldiers within SHOUT_RADIUS_METERS turn toward where he was looking.
@(private = "file")
shout :: proc(battle: ^Battle, caller: int, toward: [3]f32) {
	origin := battle.enemies[caller].controller.position
	for &other, index in battle.enemies {
		if index == caller || !Enemy_Is_Alive(other) do continue
		if la.length(other.controller.position - origin) <= SHOUT_RADIUS_METERS do Enemy_Ai_Notice(&other.ai, toward)
	}
}

// A patrolling soldier who comes across a comrade's body (within BODY_SIGHT_METERS, in front of him, in the clear) raises the
// alert at that spot. Each body is only "found" once.
@(private = "file")
discover_bodies :: proc(battle: ^Battle, finder: int) {
	enemy := &battle.enemies[finder]
	eye, forward := Enemy_Eye(enemy^), Enemy_Forward(enemy^)
	for &body, index in battle.enemies {
		if index == finder || Enemy_Is_Alive(body) || body.body_found do continue
		spot := body.controller.position + {0, 0.4, 0}
		if !Can_See(eye, forward, spot, World.Line_Of_Sight_Clear(battle.collision, battle.ground, eye, spot), BODY_SIGHT_METERS / SIGHT_RANGE_METERS) do continue
		body.body_found = true
		Enemy_Ai_Notice(&enemy.ai, body.controller.position)
		shout(battle, finder, body.controller.position)
		return
	}
}

// Sight is the cone and range test plus a ray from the enemy's eye to the player's that no wall or hill may interrupt.
@(private = "file")
enemy_senses :: proc(battle: ^Battle, enemy: Enemy) -> (senses: Ai_Senses) {
	player_eye := Player_Eye(battle.player)
	senses.player_position = battle.player.controller.position
	senses.shot_position = battle.player.controller.position
	if Health_Is_Dead(battle.player.health) do return
	eye := Enemy_Eye(enemy)
	to_player := player_eye - eye
	distance := la.length(to_player)
	clear := true
	if distance > SIGHT_RANGE_METERS * SPRINT_VISIBILITY { // Beyond anything that could be seen: skip the costly line-of-sight ray.
		senses.heard_shot = la.length(senses.player_position - enemy.controller.position) < max(Player_Noise_Radius(battle.player, false), battle.shot_noise_radius)
		return senses
	}
	if distance > 1e-3 {
		blocker := World.Raycast_World(battle.collision, battle.ground, eye, to_player / distance, distance)
		clear = !blocker.hit || blocker.distance > distance - 0.5
	}
	senses.sees_player = Can_See(eye, Enemy_Forward(enemy), player_eye, clear, Player_Visibility(battle.player))
	senses.heard_shot = la.length(senses.player_position - enemy.controller.position) < max(Player_Noise_Radius(battle.player, false), battle.shot_noise_radius)
	return senses
}

@(private = "file")
animate_enemy :: proc(enemy: ^Enemy, output: Ai_Output, wish: [2]f32, player: Player, delta_seconds: f32) {
	character := &enemy.character
	character.position = enemy.controller.position
	if la.length(output.face_direction) > 1e-4 {
		character.heading_radians = turn_toward(character.heading_radians, math.atan2(output.face_direction.x, output.face_direction.z), ENEMY_TURN_RADIANS_PER_SECOND * delta_seconds)
	}
	character.speed = la.length(wish)
	character.aiming = enemy.ai.state == .Attack || enemy.ai.state == .Alert
	if character.aiming {
		shoulder := Characters.Character_Pose(character^).joints[.Chest]
		character.aim_direction = la.normalize(Player_Eye(player) - {0, 0.3, 0} - shoulder)
	}
	Characters.Character_Step(character, delta_seconds)
}

// The enemy's shot lands with a chance that falls with distance; either way a tracer flies at the player.
@(private = "file")
enemy_fires :: proc(battle: ^Battle, index: int) {
	enemy := &battle.enemies[index]
	enemy.shot_counter += 1
	roll := proc(enemy: Enemy, salt: i32) -> f32 {
		return Procedural.Hash_To_Unit_Float(Procedural.Hash_Lattice_3(i32(enemy.shot_counter), salt, 53, enemy.seed))
	}
	player_eye := Player_Eye(battle.player)
	distance := la.length(player_eye - Enemy_Eye(enemy^))
	hit_chance := clamp(0.35 - distance * 0.007, 0.05, 0.3)
	muzzle := Enemy_Chest_Position(enemy^) + enemy.character.aim_direction * 0.6
	end := player_eye
	if roll(enemy^, 1) < hit_chance {
		zone := Hit_Zone.Head if roll(enemy^, 2) < ENEMY_HEAD_CHANCE else .Torso
		Health_Apply_Damage(&battle.player.health, ENEMY_DAMAGE * (1 - battle.player.armor), zone)
		battle.player.damage_flash = 1
	} else {
		end += {roll(enemy^, 3) * 3 - 1.5, roll(enemy^, 4) * 1.5 - 0.5, roll(enemy^, 5) * 3 - 1.5}
	}
	append(&battle.effects, Effect{kind = .Muzzle_Flash, position = muzzle, lifetime = EFFECT_FLASH_SECONDS})
	append(&battle.effects, Effect{kind = .Tracer, position = muzzle, end = end, lifetime = EFFECT_TRACER_SECONDS})
}

// A dead soldier slumps: the chest spring pulls backward and the body sinks into a crouch.
@(private = "file")
fall_after_death :: proc(enemy: ^Enemy, delta_seconds: f32) {
	enemy.death_seconds += delta_seconds
	character := &enemy.character
	character.speed, character.aiming = 0, false
	character.crouch = min(character.crouch + delta_seconds * 2, 1)
	World.Spring3_Step(&character.hit_lean, -Enemy_Forward(enemy^) * DEATH_LEAN_METERS, DEATH_FALL_FREQUENCY, delta_seconds)
}

@(private = "file")
update_projectiles :: proc(battle: ^Battle, delta_seconds: f32) {
	index := 0
	for index < len(battle.projectiles) {
		projectile := &battle.projectiles[index]
		stats := Weapons.Weapon_Stats_For(projectile.kind)
		previous := projectile.position
		gravity := GRENADE_GRAVITY if projectile.kind == .Grenade else ROCKET_GRAVITY
		World.Ballistic_Step(&projectile.body, gravity, delta_seconds)
		projectile.age += delta_seconds
		travel := projectile.position - previous
		distance := la.length(travel)
		fuse: f32 = GRENADE_FUSE_SECONDS if projectile.kind == .Grenade else ROCKET_LIFETIME_SECONDS
		detonation: Maybe([3]f32)
		if distance > 1e-5 && projectile.kind == .Grenade {
			bounce_grenade(battle^, projectile, previous, travel / distance, distance)
		} else if distance > 1e-5 {
			detonation = projectile_impact(battle^, previous, travel / distance, distance)
		}
		if position, struck := detonation.?; struck || projectile.age >= fuse {
			Battle_Detonate(battle, position if struck else projectile.position, stats.explosion_radius_meters, stats.damage)
			unordered_remove(&battle.projectiles, index)
			continue
		}
		index += 1
	}
}

// A grenade does not go off on contact: it bounces off walls and the ground, losing most of its speed (restitution 0.35 along the
// surface normal, friction 0.6 along it), and rolls to rest until its fuse burns down.
@(private = "file")
bounce_grenade :: proc(battle: Battle, grenade: ^Projectile_Entity, previous, direction: [3]f32, distance: f32) {
	hit := World.Raycast_World(battle.collision, battle.ground, previous, direction, distance)
	if !hit.hit do return
	normal := hit.normal
	velocity := grenade.velocity
	along_normal := la.dot(velocity, normal)
	if along_normal >= 0 do return
	tangent := velocity - normal * along_normal
	grenade.velocity = tangent * GRENADE_FRICTION - normal * along_normal * GRENADE_RESTITUTION
	grenade.position = hit.point + normal * 0.03
	if la.length(grenade.velocity) < 0.4 do grenade.velocity = {}
}

// Where a projectile's last step hits something solid, if it does: a wall, the ground, or a living body.
@(private = "file")
projectile_impact :: proc(battle: Battle, origin, direction: [3]f32, distance: f32) -> Maybe([3]f32) {
	nearest := distance
	hit := false
	world_hit := World.Raycast_World(battle.collision, battle.ground, origin, direction, distance)
	if world_hit.hit do nearest, hit = world_hit.distance, true
	for enemy in battle.enemies {
		if !Enemy_Is_Alive(enemy) do continue
		if body_distance, _, struck := Enemy_Raycast(enemy, origin, direction); struck && body_distance <= nearest do nearest, hit = body_distance, true
	}
	for target in battle.targets {
		if target.destroyed do continue
		if sphere := World.Ray_Sphere(origin, direction, target.position, target.radius); sphere.hit && sphere.distance <= nearest do nearest, hit = sphere.distance, true
	}
	if hit do return origin + direction * nearest
	return nil
}

@(private = "file")
update_effects :: proc(battle: ^Battle, delta_seconds: f32) {
	index := 0
	for index < len(battle.effects) {
		battle.effects[index].age += delta_seconds
		if battle.effects[index].age >= battle.effects[index].lifetime do unordered_remove(&battle.effects, index)
		else do index += 1
	}
}

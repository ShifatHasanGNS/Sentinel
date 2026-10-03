package Sandbox

import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Gameplay"
import "../Materials"
import "core:math"
import la "core:math/linalg"

PUFFS_MAX :: 1800
DECALS_MAX :: 96
DECAL_SECONDS :: 40.0

Puff_Kind :: enum {
	Muzzle_Smoke,
	Dust,
	Blast_Smoke,
	Fire,
}

// A smoke, dust or fire particle: it moves with drag, and its radius and opacity follow its age (see Particles_Collect).
Puff :: struct {
	position:  [3]f32,
	velocity:  [3]f32,
	age:       f32,
	lifetime:  f32,
	size:      f32, // Radius at birth, in meters.
	seed:      f32,
	rotation:  f32,
	kind:      Puff_Kind,
}

// A bullet hole: a dark disc lying on the surface it hit.
Decal :: struct {
	position: [3]f32,
	normal:   [3]f32,
	radius:   f32,
	age:      f32,
}

Particles :: struct {
	puffs:  [dynamic]Puff,
	decals: [dynamic]Decal,
	seed:   u32,
}

Particles_Destroy :: proc(particles: ^Particles) {
	delete(particles.puffs)
	delete(particles.decals)
}

@(private = "file")
random_unit :: proc(particles: ^Particles) -> f32 {
	particles.seed += 1
	return Procedural.Hash_To_Unit_Float(Procedural.Hash_Lattice_3(i32(particles.seed), 7, 19, 4242))
}

@(private = "file")
random_direction :: proc(particles: ^Particles) -> [3]f32 {
	z := random_unit(particles) * 2 - 1
	angle := random_unit(particles) * 2 * math.PI
	radius := math.sqrt(max(0, 1 - z * z))
	return {radius * math.cos(angle), z, radius * math.sin(angle)}
}

@(private = "file")
emit :: proc(particles: ^Particles, kind: Puff_Kind, position, velocity: [3]f32, lifetime, size: f32) {
	if len(particles.puffs) >= PUFFS_MAX do return
	append(&particles.puffs, Puff{position = position, velocity = velocity, lifetime = lifetime, size = size, seed = random_unit(particles) * 50, rotation = random_unit(particles) * 2 * math.PI, kind = kind})
}

// Effects the battle created this frame (their age is exactly one step) leave flames, smoke and holes behind.
Particles_Spawn_From_Effects :: proc(particles: ^Particles, effects: []Gameplay.Effect, delta_seconds: f32, eye: [3]f32) {
	for effect in effects {
		if effect.age > delta_seconds * 1.5 do continue
		switch effect.kind {
		case .Muzzle_Flash:
			if effect.silenced do continue
			own := la.length(effect.position - eye) < 2
			// Muzzle fire: a few hot, fast particles that live a twentieth of a second, and a thin curl of gunpowder smoke after.
			for _ in 0 ..< (2 if own else 4) do emit(particles, .Fire, effect.position, random_direction(particles) * 0.8, 0.06 + 0.04 * random_unit(particles), 0.07 if own else 0.16)
			if own do continue // The player's own muzzle is at the camera: no smoke in the face.
			for _ in 0 ..< 2 do emit(particles, .Muzzle_Smoke, effect.position, random_direction(particles) * 0.25 + {0, 0.35, 0}, 1.8, 0.1)
		case .Impact:
			for _ in 0 ..< 5 do emit(particles, .Dust, effect.position, effect.end * 1.2 + random_direction(particles) * 0.8, 1.0, 0.07)
			if la.length(effect.end) > 0.5 do add_decal(particles, effect.position, la.normalize(effect.end))
		case .Explosion:
			// The fireball: bright flames thrown outward that slow quickly, a column of dark smoke rising behind it, and dirt.
			for _ in 0 ..< 18 {
				direction := random_direction(particles)
				emit(particles, .Fire, effect.position + direction * 0.3, direction * (3 + 6 * random_unit(particles)) + {0, 1.5, 0}, 0.45 + 0.5 * random_unit(particles), 0.9 + 0.8 * random_unit(particles))
			}
			for _ in 0 ..< 26 {
				direction := random_direction(particles)
				emit(particles, .Blast_Smoke, effect.position + direction * 0.5, direction * (1 + 2.5 * random_unit(particles)) + {0, 2.5, 0}, 6 + 5 * random_unit(particles), 0.7 + 0.8 * random_unit(particles))
			}
			for _ in 0 ..< 10 do emit(particles, .Dust, effect.position, random_direction(particles) * 4 + {0, 1.5, 0}, 2.4, 0.5) // A rolling skirt of dirt.
		case .Tracer:
		}
	}
}

@(private = "file")
add_decal :: proc(particles: ^Particles, position, normal: [3]f32) {
	if len(particles.decals) >= DECALS_MAX do ordered_remove(&particles.decals, 0)
	append(&particles.decals, Decal{position = position + normal * 0.012, normal = normal, radius = 0.025 + 0.015 * random_unit(particles), age = 0})
}

Particles_Update :: proc(particles: ^Particles, delta_seconds: f32) {
	index := 0
	for index < len(particles.puffs) {
		puff := &particles.puffs[index]
		puff.age += delta_seconds
		puff.position += puff.velocity * delta_seconds
		drag: f32 = 2.8 if puff.kind == .Fire else 1.4
		puff.velocity *= math.exp(-drag * delta_seconds)
		switch puff.kind {
		case .Fire: puff.velocity.y += 2.2 * delta_seconds // Hot gas rises.
		case .Blast_Smoke, .Muzzle_Smoke: puff.velocity.y += 0.5 * delta_seconds // Warm smoke drifts up, cooling as it goes.
		case .Dust:
		}
		if puff.age >= puff.lifetime do unordered_remove(&particles.puffs, index)
		else do index += 1
	}
	index = 0
	for index < len(particles.decals) {
		particles.decals[index].age += delta_seconds
		if particles.decals[index].age >= DECAL_SECONDS do ordered_remove(&particles.decals, index)
		else do index += 1
	}
}

// One rocket-motor flame at `position`, called every frame a rocket flies; its smoke trails behind through the normal puff update.
Particles_Trail :: proc(particles: ^Particles, position: [3]f32) {
	emit(particles, .Fire, position, random_direction(particles) * 0.3, 0.12, 0.16)
	emit(particles, .Muzzle_Smoke, position, random_direction(particles) * 0.15, 2.2, 0.15)
}

// The billboards for this frame. A puff swells as it ages (smoke the most: it spreads and dilutes) and its opacity fades out through
// the last third of its life, while the shader erodes its edge, so it dissolves rather than just getting fainter.
Particles_Collect :: proc(particles: ^Particles) -> []Render.Particle {
	result := make([]Render.Particle, len(particles.puffs), context.temp_allocator)
	for puff, index in particles.puffs {
		life := clamp(puff.age / puff.lifetime, 0, 1)
		growth: f32
		opacity: f32
		tint: [3]f32
		kind := Render.Particle_Kind.Smoke
		switch puff.kind {
		case .Fire:
			kind = .Fire
			growth = 0.7 * life
			opacity = 1 - life * life
		case .Muzzle_Smoke:
			growth = 2.6 * life
			opacity = 0.32 * (1 - math.smoothstep(f32(0.45), f32(1), life))
			tint = {0.72, 0.72, 0.74}
		case .Dust:
			growth = 2.2 * life
			opacity = 0.3 * (1 - math.smoothstep(f32(0.25), f32(1), life))
			tint = {0.34, 0.28, 0.2}
		case .Blast_Smoke:
			growth = 2.4 * life
			opacity = 0.8 * (1 - math.smoothstep(f32(0.55), f32(1), life))
			cooling := math.smoothstep(f32(0), f32(0.8), life) // Black soot turns grey as it thins.
			tint = {0.05, 0.05, 0.055} + [3]f32{0.3, 0.3, 0.31} * cooling
		}
		result[index] = Render.Particle{position = puff.position, size = puff.size * (1 + growth), rotation = puff.rotation + life * 0.8, life = life, seed = puff.seed, opacity = opacity, tint = tint, kind = kind}
	}
	return result
}

// Draw items for the bullet holes still on the walls (the smoke and fire are billboards: see Particles_Collect).
Particles_Items :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item) {
	for decal in play.particles.decals {
		model := along_axis(decal.position, decal.normal) * la.matrix4_scale_f32({decal.radius, decal.radius, 0.004})
		append(items, Render.Draw_Item{mesh = &play.effect_sphere, model = model, material_layer = i32(Materials.Surface_Material.Rubber), uv_scale = {1, 1}, illumination_model = .Lambert})
	}
}

package Sandbox

import "../../Engine/Procedural"
import "../../Engine/Render"
import "../Gameplay"
import "../Materials"
import "core:math"
import la "core:math/linalg"

PUFFS_MAX :: 600
DECALS_MAX :: 96
DECAL_SECONDS :: 40.0
SMOKE_RISE_METERS_PER_SECOND :: 0.9

Puff_Kind :: enum {
	Muzzle_Smoke,
	Dust,
	Blast_Smoke,
}

// A smoke or dust puff: it drifts (rises, slows by drag), swells while young and shrinks to nothing at the end of its life, which
// stands in for dissolving because the deferred renderer draws only opaque surfaces.
Puff :: struct {
	position:  [3]f32,
	velocity:  [3]f32,
	age:       f32,
	lifetime:  f32,
	size:      f32,
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
	append(&particles.puffs, Puff{position = position, velocity = velocity, lifetime = lifetime, size = size, kind = kind})
}

// Effects the battle created this frame (their age is exactly one step) leave puffs and holes behind.
Particles_Spawn_From_Effects :: proc(particles: ^Particles, effects: []Gameplay.Effect, delta_seconds: f32, eye: [3]f32) {
	for effect in effects {
		if effect.age > delta_seconds * 1.5 do continue
		switch effect.kind {
		case .Muzzle_Flash:
			if effect.silenced || la.length(effect.position - eye) < 2 do continue // The player's own muzzle is at the camera: no smoke in the face.
			for _ in 0 ..< 2 do emit(particles, .Muzzle_Smoke, effect.position, random_direction(particles) * 0.25 + {0, 0.3, 0}, 1.4, 0.12)
		case .Impact:
			for _ in 0 ..< 4 do emit(particles, .Dust, effect.position, effect.end * 0.8 + random_direction(particles) * 0.7, 0.9, 0.08)
			if la.length(effect.end) > 0.5 do add_decal(particles, effect.position, la.normalize(effect.end))
		case .Explosion:
			for _ in 0 ..< 28 {
				direction := random_direction(particles)
				emit(particles, .Blast_Smoke, effect.position + direction * 0.4, direction * (1.5 + 3 * random_unit(particles)) + {0, 2, 0}, 6 + 4 * random_unit(particles), 0.6 + 0.7 * random_unit(particles))
			}
			for _ in 0 ..< 12 do emit(particles, .Dust, effect.position, random_direction(particles) * 6 + {0, 4, 0}, 1.4, 0.15) // Flung debris and dirt.
		case .Tracer:
		}
	}
}

@(private = "file")
add_decal :: proc(particles: ^Particles, position, normal: [3]f32) {
	if len(particles.decals) >= DECALS_MAX do ordered_remove(&particles.decals, 0)
	append(&particles.decals, Decal{position = position + normal * 0.012, normal = normal, radius = 0.025 + 0.015 * random_unit(particles)})
}

Particles_Update :: proc(particles: ^Particles, delta_seconds: f32) {
	index := 0
	for index < len(particles.puffs) {
		puff := &particles.puffs[index]
		puff.age += delta_seconds
		puff.position += puff.velocity * delta_seconds
		puff.velocity *= math.exp(-1.6 * delta_seconds)
		if puff.kind != .Dust do puff.velocity.y += SMOKE_RISE_METERS_PER_SECOND * delta_seconds * 0.3
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

// Radius factor over a puff's life: it swells quickly and keeps growing slowly as it spreads.
puff_scale :: proc(puff: Puff) -> f32 {
	t := clamp(puff.age / puff.lifetime, 0, 1)
	return (1 - math.exp(-8 * t)) * (1 + 1.6 * t)
}

// How see-through a puff is: dense when young, thinning to nothing by the end of its life (smoke dilutes as it spreads).
puff_transparency :: proc(puff: Puff) -> f32 {
	t := clamp(puff.age / puff.lifetime, 0, 1)
	base: f32 = 0.35 if puff.kind == .Blast_Smoke else 0.5
	return base + (1 - base) * t * t
}

// Draw items: puffs as grey (or brown for dust, charcoal for blasts) spheres, decals as flattened black discs.
Particles_Items :: proc(play: ^Play, items: ^[dynamic]Render.Draw_Item) {
	particles := &play.particles
	for puff in particles.puffs {
		radius := puff.size * puff_scale(puff)
		if radius < 0.005 do continue
		layer := Materials.Surface_Material.Concrete
		if puff.kind == .Dust do layer = .Sand
		if puff.kind == .Blast_Smoke do layer = .Fabric_Dark
		append(items, Render.Draw_Item{mesh = &play.effect_sphere, model = sphere_matrix(puff.position, radius), material_layer = i32(layer), uv_scale = {1, 1}, triplanar = true, illumination_model = .Oren_Nayar, transparency = puff_transparency(puff)})
	}
	for decal in particles.decals {
		model := along_axis(decal.position, decal.normal) * la.matrix4_scale_f32({decal.radius, decal.radius, 0.004})
		append(items, Render.Draw_Item{mesh = &play.effect_sphere, model = model, material_layer = i32(Materials.Surface_Material.Rubber), uv_scale = {1, 1}, illumination_model = .Lambert})
	}
}

// One puff left behind a rocket motor.
Particles_Trail :: proc(particles: ^Particles, position: [3]f32) {
	emit(particles, .Muzzle_Smoke, position, random_direction(particles) * 0.15, 1.8, 0.16)
}

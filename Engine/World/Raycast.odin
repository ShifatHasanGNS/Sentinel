package World

import "../Procedural"
import "core:math"
import la "core:math/linalg"

Collision_Box :: Procedural.Collision_Box

Ray_Hit :: struct {
	hit:      bool,
	distance: f32,
	point:    [3]f32,
	normal:   [3]f32,
}

// Slab method: the ray is inside the box exactly while it is inside all three axis slabs, so intersect the three parameter
// intervals. The face it enters through is the axis that bounds the interval from below.
Ray_Box :: proc(origin, direction: [3]f32, box: Collision_Box) -> Ray_Hit {
	nearest, farthest: f32 = -math.INF_F32, math.INF_F32
	normal: [3]f32
	for axis in 0 ..< 3 {
		if abs(direction[axis]) < 1e-9 {
			if origin[axis] < box.lowest[axis] || origin[axis] > box.highest[axis] do return {}
			continue
		}
		entry, exit := (box.lowest[axis] - origin[axis]) / direction[axis], (box.highest[axis] - origin[axis]) / direction[axis]
		if entry > exit do entry, exit = exit, entry
		if entry > nearest {
			nearest = entry
			normal = {}
			normal[axis] = -1 if direction[axis] > 0 else 1
		}
		farthest = min(farthest, exit)
		if nearest > farthest do return {}
	}
	if farthest < 0 do return {}
	if nearest < 0 do return Ray_Hit{true, 0, origin, -direction} // Starting inside.
	return Ray_Hit{true, nearest, origin + direction * nearest, normal}
}

Ray_Sphere :: proc(origin, direction, center: [3]f32, radius: f32) -> Ray_Hit {
	offset := origin - center
	half_b := la.dot(offset, direction)
	constant := la.dot(offset, offset) - radius * radius
	discriminant := half_b * half_b - constant
	if discriminant < 0 do return {}
	distance := -half_b - math.sqrt(discriminant)
	if distance < 0 {
		if constant <= 0 do return Ray_Hit{true, 0, origin, -direction} // Starting inside.
		return {}
	}
	point := origin + direction * distance
	return Ray_Hit{true, distance, point, (point - center) / radius}
}

// A capsule is the points within `radius` of the segment a-b: the side is a cylinder, each end a sphere. The nearest of the
// three hits wins; the cylinder's quadratic is solved in the frame of the segment.
Ray_Capsule :: proc(origin, direction, a, b: [3]f32, radius: f32) -> Ray_Hit {
	best := Ray_Sphere(origin, direction, a, radius)
	if end := Ray_Sphere(origin, direction, b, radius); end.hit && (!best.hit || end.distance < best.distance) do best = end
	axis := b - a
	axis_length_squared := la.dot(axis, axis)
	if axis_length_squared < 1e-12 do return best
	offset := origin - a
	axis_dot_direction := la.dot(axis, direction)
	axis_dot_offset := la.dot(axis, offset)
	k2 := axis_length_squared - axis_dot_direction * axis_dot_direction
	k1 := axis_length_squared * la.dot(offset, direction) - axis_dot_offset * axis_dot_direction
	k0 := axis_length_squared * la.dot(offset, offset) - axis_dot_offset * axis_dot_offset - radius * radius * axis_length_squared
	if k2 < 1e-9 do return best // Parallel to the axis: only the end caps can be hit.
	discriminant := k1 * k1 - k2 * k0
	if discriminant < 0 do return best
	distance := (-k1 - math.sqrt(discriminant)) / k2
	along := axis_dot_offset + distance * axis_dot_direction
	if distance >= 0 && along > 0 && along < axis_length_squared && (!best.hit || distance < best.distance) {
		point := origin + direction * distance
		best = Ray_Hit{true, distance, point, (point - a - axis * (along / axis_length_squared)) / radius}
	}
	return best
}

// The terrain is a height function, so march along the ray until it dips below the surface, then bisect that last step.
Ray_Terrain :: proc(origin, direction: [3]f32, ground: Ground, max_distance: f32) -> Ray_Hit {
	STEP :: 0.5
	if origin.y <= ground.height_at(ground.data, origin.x, origin.z) do return Ray_Hit{true, 0, origin, terrain_normal(ground, origin.x, origin.z)}
	previous: f32
	for distance := f32(STEP); previous < max_distance; distance += STEP {
		reach := min(distance, max_distance)
		point := origin + direction * reach
		if point.y <= ground.height_at(ground.data, point.x, point.z) {
			above, below := previous, reach
			for _ in 0 ..< 14 {
				middle := (above + below) / 2
				sample := origin + direction * middle
				if sample.y <= ground.height_at(ground.data, sample.x, sample.z) do below = middle
				else do above = middle
			}
			hit_point := origin + direction * below
			return Ray_Hit{true, below, hit_point, terrain_normal(ground, hit_point.x, hit_point.z)}
		}
		previous = reach
		if reach >= max_distance do break
	}
	return {}
}

@(private = "file")
terrain_normal :: proc(ground: Ground, x, z: f32) -> [3]f32 {
	step: f32 = 0.5
	slope_x := (ground.height_at(ground.data, x + step, z) - ground.height_at(ground.data, x - step, z)) / (2 * step)
	slope_z := (ground.height_at(ground.data, x, z + step) - ground.height_at(ground.data, x, z - step)) / (2 * step)
	return la.normalize([3]f32{-slope_x, 1, -slope_z})
}

World_Hit_Kind :: enum {
	None,
	Box,
	Terrain,
}

World_Hit :: struct {
	using ray: Ray_Hit,
	kind:      World_Hit_Kind,
	box_index: int,
}

@(private = "file")
closer_solid_hit :: proc(result: ^World_Hit, origin, direction: [3]f32, solid: Solid, index: int, nearest: f32) -> f32 {
	if solid.disabled do return nearest
	// Broad phase: a ray that misses the sphere around the solid cannot hit it. Costs a dot product and a compare, where Ray_Solid
	// spends two sines and two cosines turning the ray into the solid's axes.
	to_center := solid.center - origin
	along := la.dot(to_center, direction)
	radius_squared := la.dot(solid.half_extents, solid.half_extents)
	if la.dot(to_center, to_center) - along * along > radius_squared || (along < 0 && la.dot(to_center, to_center) > radius_squared) do return nearest
	hit := Ray_Solid(origin, direction, solid)
	if !hit.hit || hit.distance > nearest do return nearest
	result^ = World_Hit{ray = hit, kind = .Box, box_index = index}
	return hit.distance
}

// The nearest thing a ray strikes: any solid, or the terrain. box_index counts the long-lived solids first, then the temporary ones.
Raycast_World :: proc(world: Collision_World, ground: Ground, origin, direction: [3]f32, max_distance: f32) -> (result: World_Hit) {
	nearest := max_distance
	for solid, index in world.boxes do nearest = closer_solid_hit(&result, origin, direction, solid, index, nearest)
	for solid, index in world.temporary do nearest = closer_solid_hit(&result, origin, direction, solid, len(world.boxes) + index, nearest)
	terrain := Ray_Terrain(origin, direction, ground, nearest)
	if terrain.hit && terrain.distance <= nearest do result = World_Hit{ray = terrain, kind = .Terrain}
	return result
}

Projectile :: struct {
	position: [3]f32,
	velocity: [3]f32,
}

// Exact for constant acceleration: x' = x + v dt + g dt^2 / 2, v' = v + g dt. Any step size gives the same path.
Ballistic_Step :: proc(projectile: ^Projectile, gravity: [3]f32, delta_seconds: f32) {
	projectile.position += projectile.velocity * delta_seconds + gravity * (0.5 * delta_seconds * delta_seconds)
	projectile.velocity += gravity * delta_seconds
}

// A direction uniformly distributed over the spherical cap of half-angle `half_angle` about `aim`: pick cos(theta) uniformly
// between 1 and cos(half_angle) (equal solid angle per unit), and phi uniformly around the axis. u1 and u2 are in [0, 1).
Spread_Direction :: proc(aim: [3]f32, half_angle_radians, u1, u2: f32) -> [3]f32 {
	cosine := 1 - u1 * (1 - math.cos(half_angle_radians))
	sine := math.sqrt(max(0, 1 - cosine * cosine))
	reference: [3]f32 = {0, 1, 0} if abs(aim.y) < 0.99 else {1, 0, 0}
	right := la.normalize(la.cross(reference, aim))
	up := la.cross(aim, right)
	phi := 2 * math.PI * u2
	return la.normalize(aim * cosine + (right * math.cos(phi) + up * math.sin(phi)) * sine)
}

// Whether nothing solid (a wall, a closed door, the terrain) stands between two points, ignoring the last `margin` meters before
// `to` so a target that is itself part of a surface (a leaf, a desk against a wall) counts as reachable from the open side.
Line_Of_Sight_Clear :: proc(world: Collision_World, ground: Ground, from, to: [3]f32, margin: f32 = 0.35) -> bool {
	offset := to - from
	distance := la.length(offset)
	if distance <= margin do return true
	hit := Raycast_World(world, ground, from, offset / distance, distance)
	return !hit.hit || hit.distance > distance - margin
}

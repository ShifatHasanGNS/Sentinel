# Graphics theory referenced by code comments

Sections are added as each technique lands (GGX/Fresnel-Schlick/Smith, Oren-Nayar, periodic gradient noise, normal-from-height, triplanar mapping, cascaded shadow maps, Rayleigh/Mie scattering, two-bone IK).

## Gradient noise (Perlin 2002)
Each lattice corner contributes dot(gradient, offset to the sample). Contributions are blended with the quintic fade 6t^5 - 15t^4 + 10t^3: its first and second derivatives are zero at t = 0 and 1, so the noise is C2-continuous across cell borders. Zero at lattice points; range [-1, 1].

## Normals under deformation
A deformer is a smooth map F. Tangent directions map by the Jacobian J = dF/dp. A normal must stay perpendicular to every mapped tangent: n'.(J t) = 0 for all t, which gives n' = J^-T n. Under non-uniform scale this differs from J n.

## Periodic (tileable) noise
Wrapping the lattice coordinates modulo the period before hashing makes the noise exactly periodic: f(p + period) = f(p). fbm doubles the period with each octave's frequency so every octave still divides the tile. Worley noise places each feature point at its unwrapped neighbour position but hashes by the wrapped cell.

## Normal from height
For height h(u, v), the surface (u, v, h) has normal proportional to (-dh/du, -dh/dv, 1). Central differences give the slopes; dividing by cells per tile makes bump strength independent of tile scale.

## sRGB
Albedo is authored in linear light. It is stored in an sRGB-encoded 8-bit target (more precision in the darks) and decoded by the sampler, so shading always runs in linear space.

## Triplanar mapping
Project the texture along x, y and z and blend by |n|^4 (normalised): no UVs are needed and deformation cannot stretch the texture. Normals use the UDN blend: each projection's tangent-space xy is added to the matching components of the geometric normal.

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

## Octahedral normals
Project the unit sphere onto the octahedron |x| + |y| + |z| = 1, fold the lower hemisphere outward over the diagonals, and store two numbers in [-1, 1]. Precision is uniform over the sphere and there is no singular direction.

## Illumination models
Lambert: f = albedo / pi. Phong: lobe cos^n(R.V) normalised by (n+2)/2pi. Blinn-Phong: lobe cos^n(N.H) normalised by (n+8)/8pi. Oren-Nayar: rough diffuse, f = albedo/pi (A + B max(0, cos(phi_l - phi_v)) sin(alpha) tan(beta)) with A = 1 - 0.5 s^2/(s^2 + 0.33), B = 0.45 s^2/(s^2 + 0.09). Cook-Torrance: f = diffuse + D V F with D the GGX distribution a^2 / (pi ((n.h)^2 (a^2 - 1) + 1)^2), V the height-correlated Smith visibility G / (4 n.l n.v), F Schlick's F0 + (1 - F0)(1 - v.h)^5, and a = roughness^2. Subsurface: Cook-Torrance dielectric with the cosine wrapped, (n.l + w) / (1 + w), so light reaches slightly past the terminator.
A valid BRDF is non-negative, reciprocal (f(l,v) = f(v,l)) and conserves energy: the integral of f cos over the hemisphere is at most 1 (the white-furnace test).

## Light falloff
Inverse square times the window (1 - (d/range)^4)^2 (Karis 2013): reaches exactly zero at range with zero slope. Spot: squared smooth ramp between cos(outer) and cos(inner). Area light: an N x N grid of Lambertian point emitters, each radiating as cos(angle from the emitter normal), summed with the BRDF.

## Split-sum ambient
Specular image-based light is split into prefiltered radiance times an environment BRDF (a function of roughness and n.v only). Karis's analytic fit gives (scale, bias) so specular ambient = radiance * (F0 scale + bias).

## Cascaded shadow maps
Split the view frustum with the practical scheme: lambda * logarithmic + (1 - lambda) * uniform. Fit each slice with an orthographic box around its bounding sphere (constant size under camera rotation), moving the box centre in whole texels (no shimmer). Look up with the cascade chosen by view depth, offset the position along the normal by a texel or two to remove acne, and average a 3x3 grid of hardware depth comparisons for a soft edge.

## Tone mapping
ACES filmic curve (Narkowicz fit): (x (2.51 x + 0.03)) / (x (2.43 x + 0.59) + 0.14), clamped to [0, 1]: a toe for contrast in the darks and a shoulder that rolls highlights off instead of clipping.

## Terrain
Height = base + amplitude * fbm(x, z) * smoothstep(plateau_radius, plateau_radius + blend, distance). The smoothstep is C1, so the plateau meets the hills without a crease. Normals are central differences of the same height function, so adjacent chunks agree exactly along their shared border.

## Sun path
With latitude phi, declination delta and hour angle h (zero at noon, 15 degrees per hour): east = -cos(delta) sin(h); up = sin(phi) sin(delta) + cos(phi) cos(delta) cos(h); south = sin(phi) cos(delta) cos(h) - cos(phi) sin(delta). This vector has unit length, so it is a direction directly.

## Atmosphere
Single scattering (Nishita): along the view ray accumulate density_i * transmittance(sample to sun) * transmittance(sample to eye). Rayleigh scatter (molecules, coefficient ~ 1/wavelength^4: blue sky, red sunset) with phase 3/16pi (1 + cos^2); Mie scatter (haze, strongly forward) with the Cornette-Shanks phase. Transmittance is exp(-integral of extinction) (Beer-Lambert). Densities fall off exponentially with height at scale heights of 8 km (Rayleigh) and 1.2 km (Mie). The look-up table stores the result on an (azimuth, elevation) grid with v = 0.5 + 0.5 sign(e) sqrt(|e| / (pi/2)) so that resolution concentrates at the horizon.

## Frustum culling
Gribb-Hartmann: each of the six frustum planes is the fourth row of the view-projection matrix plus or minus another row (clip x, y, z against w). A sphere is outside if it is farther than its radius behind any plane; a box is outside if its corner furthest along a plane's normal is behind that plane.

## Eye adaptation
The exposure multiplies scene radiance before tone mapping. It rises exponentially as the sun sinks (exposure = 10^darkness), so night scenes stay readable the way the eye adapts.

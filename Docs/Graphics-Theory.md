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

## Two-bone IK
Place the middle joint (elbow, knee) so the end reaches a target. The two bones and the root-to-target line form a triangle with sides upper, lower and d = |target - root|; the law of cosines gives the angle at the root, cos(a) = (upper^2 + d^2 - lower^2) / (2 upper d). The joint lies that far along the line and off it toward a pole vector. d is clamped to [|upper - lower|, upper + lower], so an unreachable target gives a straight limb pointing at it.

## Gait
A foot's path over one cycle: during stance (fraction `duty` of the cycle) it slides back relative to the body at exactly the body's speed, so it stays fixed on the ground; during swing it eases forward along a raised arc. Stance covers `stride` in `duty * T` seconds at relative speed `speed`, hence T = stride / (duty * speed). With duty above 0.5 one foot is always planted.

## Critically damped spring
x'' = -2 w x' - w^2 x has the exact solution x(t) = (c1 + c2 t) e^(-wt) with c1 = x0 and c2 = v0 + w x0. It returns fastest without overshoot and, being exact, is independent of the time step.

## Bloom
Real lenses scatter a little light from very bright points into a halo. We approximate the wide point-spread function with a sum of blurs of growing radius: the HDR scene is downsampled through 5 half-resolution levels (13-tap filter, weights 0.5 for the centre 2x2 group and 0.125 for each corner group, which removes the flicker of small bright pixels), then each level is tent-filtered (1 2 1 / 2 4 2 / 1 2 1, divided by 16) and added onto the next larger one. A soft-knee threshold `max(s, L - T)/L` with `s = clamp(L - T + k, 0, 2k)^2 / (4k)` on the first level keeps only radiance above T = 1.2. The tonemap pass adds `strength * bloom` before exposure and ACES, so the halo is tonemapped with the scene.

## Screen-space ambient occlusion
Ambient light reaching a point P with normal n is `(1/pi) * integral V(w) cos(theta) dw` over the hemisphere, where V is visibility. We estimate V with 12 cosine-distributed points `S = P + r*k` (shorter vectors weighted more), project each into the depth buffer and count it blocked when the visible surface there is nearer the camera than S. A range term `smoothstep(r / |d_P - d_visible|)` drops occluders far in front of P, which would otherwise darken object silhouettes. The sample spiral is rotated per pixel with a 4x4 pattern and a 4x4 box blur removes it exactly. The result multiplies only the ambient term; direct sun is shadowed by the cascaded shadow maps.

## Light shafts
Single scattering along a view ray from the pixel to the sun adds `integral T(t) * S(t) dt`, where S is non-zero only where the sun is visible through that point. In screen space we march from the pixel toward the sun's projected position and sum open-sky samples (depth at the far plane) with weights `0.93^i`. Occluders (trees, buildings) between the pixel and the sun darken the sum, producing visible shafts. A per-pixel jitter of the start offset trades banding for fine noise.

## Spot-light shadows
A spot light renders the casters' depth through a perspective frustum along its axis (field of view = 2 x outer angle + 6 degrees, so the penumbra edge stays inside the map). A pixel is lit when its depth in that frustum is not behind the stored depth. Perspective depth `z' = (f+n)/(f-n) - 2fn/((f-n)z)` is non-linear, so a fixed depth bias would mean different world distances near and far; instead the lookup point is pushed along the surface normal by `distance * 2tan(fov/2)/size * (1.5 + 2.5 * tilt)` (one to four shadow texels in world units, growing with surface tilt), with a tiny constant compare bias, then 3x3 hardware-compared taps soften the edge. Only the nearest four lights that ask for a shadow get a depth layer.

## Indoor light (one-bounce radiosity stand-in)
Direct light is exact (sun with cascaded shadows, point and spot lamps with shadow maps, emissive panels). Indirect light inside a room is approximated: daylight enters by windows and doors and bounces between walls until it arrives from every direction, so the sky ambient term inside a room is scaled by 0.5 and its normal is blended 60% toward up (outdoors a ceiling faces the dark ground and would be black; indoors the lit floor and walls light it). Lamps light only the room they are in (room box test in `Shaders/Include/Interior.glsl`). Full global illumination or ray tracing is not possible in OpenGL 4.1 on macOS (no compute shaders or ray queries); this is the cheap substitute.

## Aerial perspective
Light from a surface at distance d is attenuated by Beer-Lambert, T = exp(-k d), while the air in front adds in-scattered sky light: color = mix(haze, lit, T). The haze is the atmosphere's radiance toward the horizon (so it matches the sky), k = 0.00035 per meter (about 3 km visibility).

## Soft shadow filtering
The cascade lookup averages 12 depth comparisons over a disk of 1.6 texels (plus 0.6 per cascade, since farther cascades cover more world per texel). Taps follow a Vogel spiral: tap i sits at radius sqrt((i+0.5)/N) and angle i * 2.39996 rad (the golden angle), giving equal area per tap with no clumping. The spiral is rotated per world position by a hash, turning banding into fine noise that is stable when the camera moves.

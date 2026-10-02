package Weapons

import "../../Engine/Procedural"
import "../Materials"

// Visual models only; what a weapon does (damage, fire rate) lives in Behavior.odin. Each model has its trigger grip at the
// origin, the muzzle toward +Z and the sights toward +Y.
Weapon_Kind :: enum {
	Rifle,
	Sniper_Rifle,
	Pistol,
	Rocket_Launcher,
	Grenade,
}

Weapon_Build :: proc(kind: Weapon_Kind) -> Procedural.Assembly {
	parts: [dynamic]Procedural.Part
	defer delete(parts)
	switch kind {
	case .Rifle: rifle(&parts)
	case .Sniper_Rifle: sniper_rifle(&parts)
	case .Pistol: pistol(&parts)
	case .Rocket_Launcher: rocket_launcher(&parts)
	case .Grenade: grenade(&parts)
	}
	return Procedural.Assembly_Build(parts[:])
}

@(private = "file")
Parts :: [dynamic]Procedural.Part

@(private = "file")
layer :: proc(material: Materials.Surface_Material) -> i32 {
	return i32(material)
}

@(private = "file")
box :: proc(parts: ^Parts, size, position: [3]f32, material: Materials.Surface_Material, rotation := [3]f32{}) {
	append(parts, Procedural.Part{primitive = Procedural.Box(size), position = position, rotation_degrees = rotation, material = layer(material)})
}

// A cylinder lying along Z.
@(private = "file")
barrel :: proc(parts: ^Parts, radius, length: f32, position: [3]f32, material: Materials.Surface_Material) {
	append(parts, Procedural.Part{primitive = Procedural.Cylinder(radius, length, 12), position = position, rotation_degrees = {90, 0, 0}, material = layer(material)})
}

@(private = "file")
rifle :: proc(parts: ^Parts) {
	box(parts, {0.05, 0.09, 0.3}, {0, 0.045, 0.1}, .Gunmetal)
	box(parts, {0.055, 0.06, 0.26}, {0, 0.045, 0.38}, .Rubber)
	barrel(parts, 0.011, 0.2, {0, 0.05, 0.6}, .Gunmetal)
	barrel(parts, 0.017, 0.06, {0, 0.05, 0.7}, .Gunmetal)
	box(parts, {0.008, 0.04, 0.008}, {0, 0.115, 0.67}, .Gunmetal)
	box(parts, {0.03, 0.025, 0.02}, {0, 0.1, 0}, .Gunmetal)
	box(parts, {0.035, 0.17, 0.07}, {0, -0.07, 0.12}, .Rubber, {-10, 0, 0})
	box(parts, {0.035, 0.1, 0.045}, {0, -0.05, -0.03}, .Rubber, {15, 0, 0})
	box(parts, {0.04, 0.085, 0.26}, {0, 0.02, -0.2}, .Rubber)
	box(parts, {0.045, 0.1, 0.02}, {0, 0.02, -0.33}, .Rubber)
}

@(private = "file")
sniper_rifle :: proc(parts: ^Parts) {
	box(parts, {0.05, 0.09, 0.32}, {0, 0.045, 0.12}, .Gunmetal)
	barrel(parts, 0.014, 0.62, {0, 0.05, 0.6}, .Gunmetal)
	barrel(parts, 0.02, 0.06, {0, 0.05, 0.93}, .Gunmetal)
	barrel(parts, 0.028, 0.3, {0, 0.13, 0.15}, .Gunmetal)
	barrel(parts, 0.036, 0.04, {0, 0.13, 0.32}, .Gunmetal)
	barrel(parts, 0.032, 0.04, {0, 0.13, -0.02}, .Gunmetal)
	for z in ([2]f32{0.05, 0.25}) do box(parts, {0.02, 0.05, 0.03}, {0, 0.1, z}, .Gunmetal)
	box(parts, {0.05, 0.1, 0.3}, {0, 0.02, -0.2}, .Fabric_Dark)
	box(parts, {0.045, 0.05, 0.12}, {0, 0.09, -0.16}, .Fabric_Dark)
	box(parts, {0.035, 0.1, 0.045}, {0, -0.05, -0.03}, .Fabric_Dark, {15, 0, 0})
	box(parts, {0.03, 0.08, 0.06}, {0, -0.06, 0.15}, .Gunmetal)
	for x in ([2]f32{-0.04, 0.04}) do box(parts, {0.012, 0.15, 0.012}, {x, -0.07, 0.62}, .Gunmetal, {0, 0, -x * 200})
	box(parts, {0.045, 0.1, 0.02}, {0, 0.02, -0.35}, .Rubber)
}

@(private = "file")
pistol :: proc(parts: ^Parts) {
	box(parts, {0.03, 0.1, 0.045}, {0, -0.05, -0.01}, .Rubber, {12, 0, 0})
	box(parts, {0.03, 0.035, 0.17}, {0, 0.03, 0.06}, .Gunmetal)
	barrel(parts, 0.008, 0.03, {0, 0.03, 0.16}, .Gunmetal)
	box(parts, {0.012, 0.006, 0.045}, {0, -0.005, 0.045}, .Gunmetal)
	box(parts, {0.008, 0.012, 0.008}, {0, 0.055, 0.13}, .Gunmetal)
}

@(private = "file")
rocket_launcher :: proc(parts: ^Parts) {
	barrel(parts, 0.055, 1.05, {0, 0.07, 0.3}, .Olive_Paint)
	barrel(parts, 0.075, 0.08, {0, 0.07, -0.27}, .Olive_Paint)
	barrel(parts, 0.065, 0.05, {0, 0.07, 0.84}, .Gunmetal)
	box(parts, {0.035, 0.08, 0.045}, {0, -0.03, 0}, .Rubber)
	box(parts, {0.03, 0.08, 0.04}, {0, -0.02, 0.35}, .Rubber)
	box(parts, {0.03, 0.03, 0.12}, {0, 0.145, 0.15}, .Gunmetal)
}

@(private = "file")
grenade :: proc(parts: ^Parts) {
	append(parts, Procedural.Part{primitive = Procedural.Sphere(0.035, 12, 6), stretch = {1, 1.25, 1}, material = layer(.Olive_Paint)})
	append(parts, Procedural.Part{primitive = Procedural.Cylinder(0.012, 0.025, 8), position = {0, 0.055, 0}, material = layer(.Gunmetal)})
	box(parts, {0.008, 0.06, 0.018}, {0.032, 0.02, 0}, .Gunmetal)
	append(parts, Procedural.Part{primitive = Procedural.Torus(0.014, 0.002, 12, 4), position = {0.02, 0.07, 0}, rotation_degrees = {0, 0, 90}, material = layer(.Gunmetal)})
}

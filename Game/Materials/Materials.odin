package Materials

import "../../Engine/Procedural"
import "core:slice"

MATERIAL_TEXTURE_SIZE :: 1024

// The enum value is the layer index in the baked arrays.
Surface_Material :: enum i32 {
	Concrete,
	Woodland_Camo,
	Rusted_Metal,
	Sand,
	Canvas,
	Grass,
	Dirt,
	Rock,
	Painted_Metal,
	Asphalt,
	Wood,
	Rubber,
	Glass,
	Olive_Paint,
	Skin,
	Fabric_Desert,
	Fabric_Dark,
	Gunmetal,
}

// Colours are linear RGB. detail, bump_strength and the three colours mean what each recipe shader says they mean.
@(private = "file")
recipes := [Surface_Material]Procedural.Texture_Recipe {
	.Concrete      = {"Shaders/Recipes/Concrete.glsl", 11, 4, {{0.46, 0.45, 0.43}, {0.38, 0.375, 0.36}, {}}, 0.5, 0.3},
	.Woodland_Camo = {"Shaders/Recipes/Camo.glsl", 23, 3, {{0.10, 0.15, 0.05}, {0.07, 0.045, 0.02}, {0.30, 0.25, 0.12}}, 0.5, 0.6},
	.Rusted_Metal  = {"Shaders/Recipes/RustedMetal.glsl", 37, 4, {{0.45, 0.46, 0.48}, {0.25, 0.09, 0.03}, {0.45, 0.20, 0.06}}, 0.55, 0.8},
	.Sand          = {"Shaders/Recipes/Sand.glsl", 41, 8, {{0.60, 0.48, 0.31}, {0.32, 0.25, 0.14}, {}}, 0.5, 0.5},
	.Canvas        = {"Shaders/Recipes/Canvas.glsl", 53, 8, {{0.18, 0.20, 0.10}, {0.12, 0.14, 0.07}, {}}, 0.5, 0.9},
	.Grass         = {"Shaders/Recipes/Grass.glsl", 61, 8, {{0.045, 0.085, 0.022}, {0.09, 0.15, 0.04}, {0.26, 0.22, 0.09}}, 0.5, 0.7},
	.Dirt          = {"Shaders/Recipes/Dirt.glsl", 71, 4, {{0.18, 0.12, 0.07}, {0.10, 0.07, 0.04}, {0.12, 0.105, 0.09}}, 0.5, 0.55},
	.Painted_Metal = {"Shaders/Recipes/PaintedMetal.glsl", 97, 4, {{0.16, 0.19, 0.09}, {0.50, 0.50, 0.52}, {}}, 0.5, 1.2},
	.Asphalt       = {"Shaders/Recipes/Asphalt.glsl", 101, 4, {{0.045, 0.045, 0.05}, {0.08, 0.08, 0.085}, {0.2, 0.2, 0.2}}, 0.5, 1.0},
	.Wood          = {"Shaders/Recipes/Wood.glsl", 103, 4, {{0.28, 0.17, 0.08}, {0.18, 0.1, 0.045}, {0.35, 0.22, 0.11}}, 0.5, 0.8},
	.Rubber        = {"Shaders/Recipes/Rubber.glsl", 107, 4, {{0.03, 0.03, 0.032}, {0.008, 0.008, 0.009}, {}}, 0.5, 1.5},
	.Glass         = {"Shaders/Recipes/Glass.glsl", 109, 2, {{0.02, 0.035, 0.05}, {0.06, 0.09, 0.11}, {}}, 0.5, 0.8},
	.Olive_Paint   = {"Shaders/Recipes/PaintedMetal.glsl", 113, 4, {{0.12, 0.15, 0.07}, {0.45, 0.45, 0.47}, {}}, 0, 0.35},
	.Skin          = {"Shaders/Recipes/Skin.glsl", 127, 4, {{0.42, 0.27, 0.19}, {0.36, 0.22, 0.15}, {0.5, 0.25, 0.2}}, 0.5, 0.6},
	.Fabric_Desert = {"Shaders/Recipes/Canvas.glsl", 131, 8, {{0.38, 0.30, 0.18}, {0.28, 0.22, 0.13}, {}}, 0.5, 0.9},
	.Fabric_Dark   = {"Shaders/Recipes/Canvas.glsl", 137, 8, {{0.06, 0.07, 0.06}, {0.035, 0.04, 0.035}, {}}, 0.5, 0.9},
	.Gunmetal      = {"Shaders/Recipes/PaintedMetal.glsl", 139, 4, {{0.03, 0.03, 0.035}, {0.28, 0.28, 0.3}, {}}, 0, 1.2},
	.Rock          = {"Shaders/Recipes/Rock.glsl", 83, 4, {{0.30, 0.29, 0.27}, {0.14, 0.13, 0.12}, {}}, 0.5, 1.0},
}

Materials_Recipes :: proc() -> [Surface_Material]Procedural.Texture_Recipe {
	return recipes
}

Materials_Bake :: proc() -> (set: Procedural.Texture_Set, ok: bool) {
	return Procedural.Texture_Set_Bake(slice.enumerated_array(&recipes), MATERIAL_TEXTURE_SIZE)
}

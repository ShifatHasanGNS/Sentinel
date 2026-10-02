package Materials

import "../../Engine/Procedural"
import "core:slice"

MATERIAL_TEXTURE_SIZE :: 512

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
}

// Colours are linear RGB. detail, bump_strength and the three colours mean what each recipe shader says they mean.
@(private = "file")
recipes := [Surface_Material]Procedural.Texture_Recipe {
	.Concrete      = {"Shaders/Recipes/Concrete.glsl", 11, 4, {{0.42, 0.42, 0.40}, {0.30, 0.30, 0.29}, {}}, 0.5, 0.8},
	.Woodland_Camo = {"Shaders/Recipes/Camo.glsl", 23, 3, {{0.10, 0.15, 0.05}, {0.07, 0.045, 0.02}, {0.30, 0.25, 0.12}}, 0.5, 0.6},
	.Rusted_Metal  = {"Shaders/Recipes/RustedMetal.glsl", 37, 4, {{0.45, 0.46, 0.48}, {0.25, 0.09, 0.03}, {0.45, 0.20, 0.06}}, 0.55, 0.8},
	.Sand          = {"Shaders/Recipes/Sand.glsl", 41, 8, {{0.60, 0.48, 0.31}, {0.32, 0.25, 0.14}, {}}, 0.5, 0.5},
	.Canvas        = {"Shaders/Recipes/Canvas.glsl", 53, 8, {{0.18, 0.20, 0.10}, {0.12, 0.14, 0.07}, {}}, 0.5, 0.9},
	.Grass         = {"Shaders/Recipes/Grass.glsl", 61, 8, {{0.05, 0.12, 0.02}, {0.12, 0.25, 0.04}, {0.30, 0.28, 0.08}}, 0.5, 0.7},
	.Dirt          = {"Shaders/Recipes/Dirt.glsl", 71, 4, {{0.18, 0.12, 0.07}, {0.10, 0.07, 0.04}, {0.20, 0.18, 0.15}}, 0.5, 0.9},
	.Painted_Metal = {"Shaders/Recipes/PaintedMetal.glsl", 97, 4, {{0.16, 0.19, 0.09}, {0.50, 0.50, 0.52}, {}}, 0.5, 1.2},
	.Rock          = {"Shaders/Recipes/Rock.glsl", 83, 4, {{0.30, 0.29, 0.27}, {0.14, 0.13, 0.12}, {}}, 0.5, 1.0},
}

Materials_Recipes :: proc() -> [Surface_Material]Procedural.Texture_Recipe {
	return recipes
}

Materials_Bake :: proc() -> (set: Procedural.Texture_Set, ok: bool) {
	return Procedural.Texture_Set_Bake(slice.enumerated_array(&recipes), MATERIAL_TEXTURE_SIZE)
}

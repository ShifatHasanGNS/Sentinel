package Render

// Values match the MODEL_* constants in Shaders/Include/Brdf.glsl; the model id is stored per pixel in the G-buffer.
Illumination_Model :: enum i32 {
	Lambert,
	Phong,
	Blinn_Phong,
	Oren_Nayar,
	Cook_Torrance,
	Subsurface,
}

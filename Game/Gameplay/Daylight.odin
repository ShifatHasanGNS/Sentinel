package Gameplay

import "../../Engine/Render"
import "core:math/linalg"

ATMOSPHERE_SUN_INTENSITY :: 20.0

Daylight :: struct {
	sun: Render.Light, // The one directional light: the sun by day, the moon by night.
	sky: Render.Sky,
	exposure: f32,
}

// Everything lighting depends on at a given hour. At night the directional light switches to the moon.
Daylight_For_Hours :: proc(hours: f32) -> Daylight {
	to_sun := Sun_Direction_To_Sun(hours)
	sunlight := Sunlight_For_Elevation(to_sun.y)
	moonlight := Moonlight_For_Sun(to_sun)
	colors := Sky_Colors_For_Sun(to_sun)
	sun_light := Render.Light_Directional(-to_sun, sunlight.color, sunlight.intensity)
	if sunlight.intensity < moonlight.intensity do sun_light = Render.Light_Directional(-moonlight.to_moon, moonlight.color, moonlight.intensity)
	return Daylight{
		exposure = Exposure_For_Elevation(to_sun.y),
		sun = sun_light,
		sky = Render.Sky{
			zenith = colors.zenith,
			horizon = colors.horizon,
			ground = colors.ground,
			sun_color = sunlight.color,
			to_sun = to_sun,
			sun_intensity = ATMOSPHERE_SUN_INTENSITY,
			to_moon = moonlight.to_moon,
			moon_color = moonlight.color,
			moon_intensity = moonlight.intensity,
		},
	}
}

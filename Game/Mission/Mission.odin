package Mission

HACK_SECONDS :: 2.5 // Holding E at the computer this long breaks into it.
HACK_DECAY_FACTOR :: 2.0 // Progress drains this many times faster than it builds once you let go.

Objective :: enum {
	Enter_Compound,
	Hack_Cameras,
	Destroy_Radar,
	Rescue_Hostage,
	Destroy_Fuel,
	Reach_Extraction,
}

// The missions on offer, each a different subset of the objectives.
Variant :: enum {
	Rescue, // Daylight infiltration: hack, radar, hostage.
	Night_Raid, // After dark: hack, radar, and blow up the fuel depot; nobody to rescue.
}

Variant_Objectives :: proc(variant: Variant) -> bit_set[Objective] {
	switch variant {
	case .Rescue: return {.Enter_Compound, .Hack_Cameras, .Destroy_Radar, .Rescue_Hostage, .Reach_Extraction}
	case .Night_Raid: return {.Enter_Compound, .Hack_Cameras, .Destroy_Radar, .Destroy_Fuel, .Reach_Extraction}
	}
	unreachable()
}

Variant_Name :: proc(variant: Variant) -> string {
	switch variant {
	case .Rescue: return "OPERATION SENTINEL"
	case .Night_Raid: return "NIGHT RAID"
	}
	unreachable()
}

Mission_Status :: enum {
	Briefing,
	Active,
	Complete,
}

// The mission's progress. Which objectives are done, how far the hack has got, and which finished on the latest update (for the
// on-screen "objective complete" notices).
Mission :: struct {
	variant:           Variant,
	required:          bit_set[Objective], // The objectives this mission asks for; the rest never appear.
	status:            Mission_Status,
	done:              [Objective]bool,
	just_completed:    bit_set[Objective],
	hack_seconds:      f32,
	elapsed_seconds:   f32,
}

// What the world says about the player this frame; the mission itself knows nothing about positions.
Observation :: struct {
	inside_compound:   bool,
	terminal_in_reach: bool,
	interact_held:     bool, // E is down.
	hostage_in_reach:  bool,
	interact_pressed:  bool, // E went down this frame.
	radar_destroyed:   bool,
	fuel_destroyed:    bool,
	at_extraction:     bool,
}

Mission_Create :: proc(variant: Variant = .Rescue) -> Mission {
	return Mission{variant = variant, required = Variant_Objectives(variant)}
}

Mission_Start :: proc(mission: ^Mission) {
	if mission.status == .Briefing do mission.status = .Active
}

// Enter the compound first; then hack the cameras, destroy the radar and rescue the hostage in any order (the radar may even be
// destroyed from outside); extraction opens once all three are done.
Mission_Update :: proc(mission: ^Mission, observation: Observation, delta_seconds: f32) {
	mission.just_completed = {}
	if mission.status != .Active do return
	mission.elapsed_seconds += delta_seconds
	if observation.inside_compound do complete(mission, .Enter_Compound)
	update_hack(mission, observation, delta_seconds)
	if observation.radar_destroyed do complete(mission, .Destroy_Radar)
	if observation.fuel_destroyed && .Destroy_Fuel in mission.required do complete(mission, .Destroy_Fuel)
	if observation.hostage_in_reach && observation.interact_pressed && .Rescue_Hostage in mission.required do complete(mission, .Rescue_Hostage)
	ready := true // Extraction opens once every required task between entering and leaving is done.
	for objective in Objective {
		if objective in mission.required && objective != .Enter_Compound && objective != .Reach_Extraction && !mission.done[objective] do ready = false
	}
	if ready && observation.at_extraction {
		complete(mission, .Reach_Extraction)
		mission.status = .Complete
	}
}

@(private = "file")
complete :: proc(mission: ^Mission, objective: Objective) {
	if mission.done[objective] do return
	mission.done[objective] = true
	mission.just_completed += {objective}
}

@(private = "file")
update_hack :: proc(mission: ^Mission, observation: Observation, delta_seconds: f32) {
	if mission.done[.Hack_Cameras] do return
	if observation.terminal_in_reach && observation.interact_held {
		mission.hack_seconds += delta_seconds
		if mission.hack_seconds >= HACK_SECONDS {
			mission.hack_seconds = HACK_SECONDS
			complete(mission, .Hack_Cameras)
		}
	} else {
		mission.hack_seconds = max(mission.hack_seconds - delta_seconds * HACK_DECAY_FACTOR, 0)
	}
}

// The first objective not yet done, in the listed order: what the HUD points at. Nothing once the mission is complete.
Mission_Current_Objective :: proc(mission: Mission) -> (objective: Objective, any: bool) {
	for candidate in Objective {
		if candidate in mission.required && !mission.done[candidate] do return candidate, true
	}
	return {}, false
}

Objective_Text :: proc(objective: Objective) -> string {
	switch objective {
	case .Enter_Compound: return "GET INSIDE THE COMPOUND"
	case .Hack_Cameras: return "HACK THE CAMERA COMPUTER IN THE HQ"
	case .Destroy_Radar: return "DESTROY THE RADAR STATION"
	case .Rescue_Hostage: return "RESCUE THE HOSTAGE IN THE BARRACKS"
	case .Destroy_Fuel: return "BLOW UP THE TWO FUEL TANKS"
	case .Reach_Extraction: return "REACH THE EXTRACTION POINT"
	}
	return ""
}

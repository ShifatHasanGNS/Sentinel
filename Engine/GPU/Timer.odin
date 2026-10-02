package GPU

import gl "vendor:OpenGL"

// Measures GPU time spent between Begin and End. Two queries alternate so a result is read a frame after it was written,
// never stalling the pipeline. Timer queries of the same kind cannot nest.
Timer :: struct {
	queries:                  [2]u32,
	frame:                    int,
	accumulated_milliseconds: f64,
	sample_count:             int,
}

Timer_Create :: proc() -> (timer: Timer) {
	gl.GenQueries(2, &timer.queries[0])
	return timer
}

Timer_Destroy :: proc(timer: ^Timer) {
	gl.DeleteQueries(2, &timer.queries[0])
}

Timer_Begin :: proc(timer: ^Timer) {
	gl.BeginQuery(gl.TIME_ELAPSED, timer.queries[timer.frame % 2])
}

Timer_End :: proc(timer: ^Timer) {
	gl.EndQuery(gl.TIME_ELAPSED)
	timer.frame += 1
}

// Reads the previous measurement if it has finished.
Timer_Collect :: proc(timer: ^Timer) {
	if timer.frame == 0 do return
	previous := timer.queries[(timer.frame - 1) % 2]
	available: i32
	gl.GetQueryObjectiv(previous, gl.QUERY_RESULT_AVAILABLE, &available)
	if available == 0 do return
	nanoseconds: u32
	gl.GetQueryObjectuiv(previous, gl.QUERY_RESULT, &nanoseconds)
	timer.accumulated_milliseconds += f64(nanoseconds) / 1e6
	timer.sample_count += 1
}

Timer_Average_Milliseconds :: proc(timer: Timer) -> f32 {
	return f32(timer.accumulated_milliseconds / f64(max(timer.sample_count, 1)))
}

Timer_Reset :: proc(timer: ^Timer) {
	timer.accumulated_milliseconds = 0
	timer.sample_count = 0
}

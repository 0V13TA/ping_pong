package main

import "base:runtime"
import rl "vendor:raylib"

// -----------------------------------------------------------------------------
// PLATFORM SPECIFIC ENTRY POINTS
// -----------------------------------------------------------------------------

// 1. DESKTOP ENTRY POINT (Linux / Windows)
// Odin finds this automatically when compiling for desktop
main :: proc() {
	// Desktop specific config (e.g., fixed window size)
	rl.InitWindow(800, 480, "Ping Pong Desktop")

	game_run() // Jump to shared code
}

// 2. ANDROID ENTRY POINT
// The Android NDK looks for this specific C function
AndroidApp :: struct {} // Opaque handle

@(export)
android_main :: proc "c" (app: ^AndroidApp) {
	// Android specific context setup
	context = runtime.default_context()

	// On Android, (0, 0) tells Raylib to use the full native screen resolution
	rl.InitWindow(0, 0, "Ping Pong Android")

	game_run() // Jump to shared code
}

// -----------------------------------------------------------------------------
// SHARED GAME LOGIC
// -----------------------------------------------------------------------------

game_run :: proc() {
	// Load assets, setup variables, etc.
	width := rl.GetScreenWidth()
	height := rl.GetScreenHeight()

	rl.SetTargetFPS(60)

	// Main Loop
	for !rl.WindowShouldClose() {
		// Update Logic here
		// ...

		// Draw
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)

		rl.DrawCircle(width / 2, height / 2, 50, rl.RED)
		rl.DrawText("Run anywhere!", 20, 20, 30, rl.BLACK)

		rl.EndDrawing()
	}

	// Cleanup
	rl.CloseWindow()
}

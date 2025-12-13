package main

import "base:runtime"
import rl "vendor:raylib"

// Config flag passed from build script
ANDROID :: #config(ANDROID, false)

// 1. DESKTOP ENTRY POINT
when !ANDROID {
	main :: proc() {
		rl.InitWindow(800, 480, "Ping Pong Desktop")
		game_run()
	}
}

// 2. ANDROID ENTRY POINT
when ANDROID {
	AndroidApp :: struct {}

	@(export)
	android_main :: proc "c" (app: ^AndroidApp) {
		context = runtime.default_context()
		rl.InitWindow(0, 0, "Ping Pong Android")
		game_run()
	}
	// REMOVED: main_dummy
}

// SHARED GAME LOGIC
game_run :: proc() {
	width := rl.GetScreenWidth()
	height := rl.GetScreenHeight()
	fontSize: i32 = i32(width) / 20

	rl.SetTargetFPS(60)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.RAYWHITE)
		rl.DrawCircle(width / 2, height / 2, f32(width) / 4, rl.MAROON)
		rl.DrawText("IT WORKS!", 50, height / 2 - 50, fontSize, rl.WHITE)
		rl.DrawFPS(20, 20)
		rl.EndDrawing()
	}

	rl.CloseWindow()
}

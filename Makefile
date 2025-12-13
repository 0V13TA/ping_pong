# Project Name
NAME = game

# Directories
BUILD_DIR = build

# Detect OS for "make run"
UNAME_S := $(shell uname -s)

# Targets
.PHONY: all linux windows android clean run install

# Default target (compiles for your current system)
all: linux

# 1. Linux Build
linux:
	@echo "-> Building for Linux..."
	@mkdir -p $(BUILD_DIR)
	odin build src -out:$(BUILD_DIR)/$(NAME)_linux.bin -debug
	@echo "-> Done: $(BUILD_DIR)/$(NAME)_linux.bin"

# 2. Windows Build (Cross-compile)
windows:
	@echo "-> Building for Windows..."
	@mkdir -p $(BUILD_DIR)
	odin build src -out:$(BUILD_DIR)/windows/$(NAME).exe -target:windows_amd64
	@echo "-> Done: $(BUILD_DIR)/$(NAME).exe"

# 3. Android Build (Delegates to script)
android:
	@chmod +x build_android.sh
	@./build_android.sh

# 4. Clean everything
clean:
	@echo "-> Cleaning up..."
	rm -rf build/
	rm -rf android/build/
	adb uninstall com.raylib.game
	@echo "-> Cleaned."

# 5. Run the Linux binary
run: linux
	@echo "-> Running..."
	./$(BUILD_DIR)/linux/$(NAME)_linux.bin

# 6. Install to Android Device (Shortcut)
install:
	adb install -r ./${BUILD_DIR}/android/$(NAME)_android.apk

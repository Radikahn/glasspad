# Glasspad tasks — run `just` to list them.

app := "build/Build/Products/Release/Glasspad.app"
debug_app := "build/Build/Products/Debug/Glasspad.app"
arch := `uname -m`
db := home_directory() / "Library/Application Support/Glasspad/glasspad.sqlite"

# List available recipes
default:
    @just --list --unsorted

# Build and launch the app (relaunches it if already open)
run: build quit
    open "{{app}}"

# Build a debug app and run it in the foreground, logging to this terminal
dev: (build "debug") quit
    "{{debug_app}}/Contents/MacOS/Glasspad"

# Run the offscreen editor tests (snapshots are written to build/test)
test:
    mkdir -p build/test
    xcrun swiftc -swift-version 5 -O -o build/test/editor-harness \
        Tests/EditorHarness/main.swift Glasspad/Editor/*.swift
    build/test/editor-harness build/test

# Build the app; config is release or debug
build config="release": project
    xcodebuild -project Glasspad.xcodeproj -scheme Glasspad \
        -configuration {{capitalize(config)}} \
        -destination 'platform=macOS,arch={{arch}}' \
        -derivedDataPath build -quiet build

# Install into /Applications
install: build quit
    rm -rf /Applications/Glasspad.app
    cp -R "{{app}}" /Applications/
    @echo "Installed /Applications/Glasspad.app"

# Quit a running Glasspad (it saves pending edits first)
quit:
    #!/usr/bin/env bash
    pkill -x Glasspad || exit 0
    for _ in {1..50}; do
        pgrep -x Glasspad >/dev/null || exit 0
        sleep 0.1
    done
    echo "Glasspad did not quit in time; forcing it" >&2
    pkill -9 -x Glasspad || true

# Generate Glasspad.xcodeproj from project.yml
project:
    @xcodegen generate --quiet

# Open the project in Xcode
xcode: project
    open Glasspad.xcodeproj

# Open a sqlite3 shell on the entries database
db:
    sqlite3 "{{db}}"

# Forget the saved window size so the next launch uses the default
reset-window: quit
    -defaults delete com.radikahn.glasspad

# Delete build output
clean:
    rm -rf build

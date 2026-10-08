# Glasspad

A minimal glass journal for macOS: live-rendered markdown, a small vim layer, and a smearing cursor.

## Build

Requires Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and [just](https://github.com/casey/just)
(`brew install xcodegen just`).

```sh
just              # list every recipe
just run          # build and launch (relaunches if already open)
just dev          # debug build in the foreground, logs in the terminal
just test         # offscreen editor tests
just install      # copy Glasspad.app into /Applications
```

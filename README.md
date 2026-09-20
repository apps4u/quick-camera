# Quick Camera

Quick Camera is a macOS utility to display the output from any USB-based camera on your desktop. Quick Camera is often used for presentations where you need to show the output from an external device to your audience. 

Quick Camera supports mirroring (normal and reversed, both vertical and horizontal), can be rotated, resized to any size, and the window can be placed in the foreground.

You can find the original app on the Mac App Store: https://itunes.apple.com/us/app/qcamera/id598853070?mt=12

## About this fork

I needed an app that could display a USB camera feed while letting me take snapshots **without using my hands**. My USB camera has a hardware snap button, but on macOS it never sends the snap signal — Apple's UVC driver owns the camera's control interface, so the button press never reaches the app. Since the hardware route was a dead end, I made it a voice command instead: say **"snap"** and the app captures a shot. I was building this with AI assistance anyway, so why not.

What this fork adds on top of the original Quick Camera:

- **Snapshot capture** — saves the current frame as a PNG, silently, to a folder you choose once (a brief white flash confirms the capture)
- **Hands-free capture** — opt-in "Listen for “Snap”" voice command, transcribed fully on-device with Apple's SpeechAnalyzer (no audio leaves your Mac)
- **Unit tests** — rotation maths, snapshot filename handling, voice-trigger matching, and settings persistence are extracted into testable types with a Swift Testing test target
- **Modernised concurrency** — `@MainActor` isolation and async/await throughout

## Building Quick Camera

Quick Camera can be built using XCode. Download XCode from https://developer.apple.com/xcode/ and open the Quick Camera.xcodeproj file.

In addition, with XCode or the XCode Command Line Tools installed, Quick Camera can also be built using the command line:

```bash
xcodebuild -scheme Quick\ Camera -configuration Release clean build
```

Upon successful build, Quick Camera can be launched with:

```bash
open build/release/Quick\ Camera.app
```

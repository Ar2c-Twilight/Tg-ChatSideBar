# TgChatSideBar

An iOS app built entirely in code — **no storyboards, no XIBs**.

## Requirements

- Xcode 16 or newer
- iOS 17.0+ deployment target
- Swift 5

## Getting started

```sh
open TgChatSideBar.xcodeproj
```

Select the `TgChatSideBar` scheme and run on a simulator or device.

Command line builds:

```sh
xcodebuild -project TgChatSideBar.xcodeproj \
           -scheme TgChatSideBar \
           -destination 'platform=iOS Simulator,name=iPhone 16' \
           build
```

## Layout

```
TgChatSideBar/
├── AppDelegate.swift      App lifecycle + scene configuration
├── SceneDelegate.swift    Creates the UIWindow and sets the root view controller
├── ViewController.swift   Root view controller (intentionally empty)
├── Assets.xcassets        App icon and accent color
└── Info.plist             Scene manifest, no storyboard entries
```

## How the storyboard-free setup works

- `Info.plist` has **no** `UIMainStoryboardFile` key, and the scene configuration
  under `UIApplicationSceneManifest` declares only
  `UISceneDelegateClassName` — no `UISceneStoryboardFile`.
- The launch screen is the storyboard-free `UILaunchScreen` dictionary rather
  than `UILaunchStoryboardName`.
- `SceneDelegate.scene(_:willConnectTo:options:)` builds the `UIWindow` and
  root view controller programmatically.

Build UI with code (`UIView` subclasses + Auto Layout anchors); do not add
`.storyboard` or `.xib` files.

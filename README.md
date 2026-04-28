# FrameBlaster

<img width="1536" height="1024" alt="frameblaster2k" src="https://github.com/user-attachments/assets/cada0fa4-af7b-42e8-9e4b-3b65031f5c61" />

FrameBlaster is a Swift package that adds frame-based animation helpers directly to `UIImageView`.

It provides two animation paths:

- `playPerformanceAnimation`: streams file-backed frames as compressed data and creates images on demand, prioritizing low retained memory.
- `playAssetCatalogAnimation`: a convenience wrapper around UIKit's standard `UIImageView.animationImages` path for frames stored in an asset catalog.

FrameBlaster started before asset catalogs were a thing. Its original reason for existing was memory performance: large `UIImageView.animationImages` arrays could retain decoded frame sets and quickly create memory spikes. Modern asset catalogs have changed that picture a lot, and in many cases Apple's current animation path is excellent. FrameBlaster is still useful when you want a memory-first animation path, predictable frame naming, completion handling, current-frame inspection, and a compact API for working with frame sequences.

## Requirements

- iOS 13+
- Swift 6.3

## Installation

Add FrameBlaster with Swift Package Manager.

In Xcode:

1. Choose **File > Add Package Dependencies...**
2. Enter the repository URL:

```text
https://github.com/mbehan/animation-view.git
```

3. Add the `FrameBlaster` product to your app target.

Or add it to another Swift package.

```swift
.package(url: "https://github.com/mbehan/FrameBlaster.git", from: "1.0.0")
```

Then add the product to your target dependencies:

```swift
.product(name: "FrameBlaster", package: "FrameBlaster")
```

## Quick Start

Import FrameBlaster and call the animation helper on any `UIImageView`.

```swift
import UIKit
import FrameBlaster

let imageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 350, height: 285))

imageView.playPerformanceAnimation(
    "animationFrame",
    range: 0..<80,
    numberPadding: 2,
    fps: 24,
    repeat: 0
)
```

With `animationName` set to `"animationFrame"`, `range` set to `0..<80`, and `numberPadding` set to `2`, FrameBlaster looks for frames named:

```text
animationFrame00
animationFrame01
animationFrame02
...
animationFrame79
```

A repeat count of `0` means repeat forever. Any positive value plays that many times.

## Performance Animation

Use the performance path when avoiding decoded-frame memory spikes is the priority.

```swift
imageView.playPerformanceAnimation(
    "spinner",
    range: 0..<120,
    numberPadding: 3,
    fps: 24,
    repeat: 1,
    completion: {
        print("Finished")
    }
)
```

You can also create and start the image view in one call:

```swift
let imageView = UIImageView(
    performanceAnimationNamed: "spinner",
    range: 0..<120,
    numberPadding: 3,
    fps: 24,
    repeat: 1
)
```

The performance path loads frame files from the bundle as compressed `Data`, then creates each `UIImage` when it is needed for display. It supports these file types:

- `png`
- `jpg`
- `jpeg`
- `heic`
- `webp`

For file-backed frames, include files in your app bundle with names such as:

```text
spinner000.png
spinner001.png
spinner002.png
```

Scale-specific files such as `spinner000@2x.png` and `spinner000@3x.png` are also supported.

## Asset Catalog Animation

Use the asset catalog path when you want UIKit's standard animation behavior with a convenient frame-sequence API.

```swift
imageView.playAssetCatalogAnimation(
    "spinner",
    range: 0..<120,
    numberPadding: 3,
    fps: 24,
    repeat: 1
)
```

This path loads frames with `UIImage(named:in:compatibleWith:)`, assigns them to `animationImages`, sets `animationDuration`, and calls `startAnimating()`.

You can also create and start the image view in one call:

```swift
let imageView = UIImageView(
    assetCatalogAnimationNamed: "spinner",
    range: 0..<120,
    numberPadding: 3,
    fps: 24,
    repeat: 1
)
```

## Controlling Playback

FrameBlaster adds a few helpers to `UIImageView`:

```swift
imageView.stopFrameBlasterPerformanceAnimation()
imageView.stopFrameBlasterAnimation()

let frameNumber = imageView.frameBlasterCurrentFrameNumber
let frameImage = imageView.frameBlasterCurrentFrameImage
let isAnimating = imageView.isFrameBlasterPerformanceAnimating
```

`stopFrameBlasterPerformanceAnimation()` stops only the performance path. `stopFrameBlasterAnimation()` stops either FrameBlaster path, cancels any scheduled completion, stops UIKit animation, and clears `animationImages`.

## Choosing an Animation Path

FrameBlaster's `playPerformanceAnimation` path is a memory-first, CPU-for-memory tradeoff.

It avoids retaining decoded frame sets almost entirely. Across 10, 100, and 240 frames in the tests below, its peak physical-footprint delta stayed at `0.00 MB`. Compared with manual `UIImageView.animationImages`, which reached about `470 MB` at 100 frames and about `1.1 GB` at 240 frames, the performance path is dramatically better for memory pressure.

The cost is CPU and setup time:

- Load time is consistently slower than asset catalog for larger frame counts.
- CPU scales with FPS: about `20%` at 12 fps, `28%` at 24 fps, and `48-49%` at 60 fps.
- Peak CPU is often around one saturated core, and sometimes above `100%` due to sampling and thread accounting.

Asset catalog animation is surprisingly strong in these tests. It has low load time, low CPU, and only small physical-footprint deltas in a fresh process. That suggests Apple's current asset catalog path is much better than older assumptions, at least when measured with `phys_footprint` during playback. Be cautious when generalising from that number, though: system/shared caches and memory accounting may not show up the same way as explicit `UIImage` arrays.

Manual `UIImageView.animationImages` is the worst option for large sequences: high load time, huge memory footprint, and rising CPU for large or high-FPS cases.

Practical guidance:

- Use `playPerformanceAnimation` when avoiding memory spikes is the priority, especially for long frame sequences or memory-constrained contexts.
- Use `playAssetCatalogAnimation` when you want low CPU, fast startup, and the asset catalog pipeline is acceptable.
- Avoid manually building large `animationImages` arrays unless the sequence is small or memory is known to be safe.

## Performance Test Results

| Frames | FPS | Option | Load ms | Base footprint MB | Avg footprint MB | Peak footprint MB | Avg delta MB | Peak delta MB | Avg CPU % | Peak CPU % |
| ---: | ---: | :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 12 | Asset catalog | 1.45 | 29.16 | 29.20 | 29.21 | 0.05 | 0.05 | 2.39 | 56.97 |
| 1 | 12 | Performance | 0.31 | 29.11 | 29.17 | 29.17 | 0.06 | 0.06 | 5.83 | 98.51 |
| 1 | 12 | UIImageView animationImages | 31.94 | 30.44 | 26.10 | 30.44 | 0.00 | 0.00 | 4.09 | 105.49 |
| 1 | 24 | Asset catalog | 0.98 | 29.10 | 29.28 | 29.56 | 0.18 | 0.47 | 3.73 | 99.37 |
| 1 | 24 | Performance | 0.28 | 29.16 | 29.23 | 29.24 | 0.08 | 0.08 | 4.13 | 96.81 |
| 1 | 24 | UIImageView animationImages | 24.79 | 29.16 | 24.57 | 29.16 | 0.00 | 0.00 | 4.72 | 103.25 |
| 1 | 60 | Asset catalog | 0.78 | 29.24 | 29.30 | 29.30 | 0.06 | 0.06 | 4.86 | 98.56 |
| 1 | 60 | Performance | 0.25 | 29.14 | 29.25 | 29.25 | 0.11 | 0.11 | 5.37 | 96.47 |
| 1 | 60 | UIImageView animationImages | 22.44 | 29.14 | 24.52 | 29.14 | 0.00 | 0.00 | 4.34 | 106.03 |
| 10 | 12 | Asset catalog | 3.95 | 29.22 | 29.43 | 29.44 | 0.21 | 0.22 | 3.77 | 71.27 |
| 10 | 12 | Performance | 21.77 | 29.11 | 28.48 | 29.11 | 0.00 | 0.00 | 20.46 | 101.76 |
| 10 | 12 | UIImageView animationImages | 24.45 | 29.17 | 63.35 | 65.02 | 34.37 | 35.84 | 5.12 | 100.34 |
| 10 | 24 | Asset catalog | 1.24 | 29.19 | 29.42 | 29.42 | 0.23 | 0.23 | 5.38 | 99.29 |
| 10 | 24 | Performance | 23.96 | 29.19 | 28.67 | 29.19 | 0.00 | 0.00 | 26.49 | 104.50 |
| 10 | 24 | UIImageView animationImages | 23.65 | 29.24 | 63.46 | 65.13 | 34.41 | 35.89 | 4.86 | 100.75 |
| 10 | 60 | Asset catalog | 1.23 | 29.11 | 29.32 | 29.33 | 0.21 | 0.22 | 5.18 | 99.36 |
| 10 | 60 | Performance | 20.74 | 29.24 | 28.75 | 29.24 | 0.00 | 0.00 | 47.61 | 103.87 |
| 10 | 60 | UIImageView animationImages | 24.94 | 29.11 | 63.34 | 65.02 | 34.42 | 35.91 | 4.38 | 100.77 |
| 100 | 12 | Asset catalog | 22.75 | 29.22 | 29.93 | 29.96 | 0.71 | 0.73 | 3.24 | 63.40 |
| 100 | 12 | Performance | 27.06 | 29.24 | 28.45 | 29.24 | 0.00 | 0.00 | 19.75 | 103.40 |
| 100 | 12 | UIImageView animationImages | 90.91 | 29.24 | 410.82 | 470.21 | 382.16 | 440.97 | 19.17 | 110.05 |
| 100 | 24 | Asset catalog | 3.01 | 29.19 | 29.88 | 29.91 | 0.69 | 0.72 | 6.14 | 99.75 |
| 100 | 24 | Performance | 25.71 | 29.16 | 28.61 | 29.16 | 0.00 | 0.00 | 28.07 | 103.93 |
| 100 | 24 | UIImageView animationImages | 50.62 | 29.16 | 406.54 | 470.17 | 378.00 | 441.02 | 15.13 | 99.23 |
| 100 | 60 | Asset catalog | 2.65 | 29.17 | 29.87 | 29.89 | 0.69 | 0.72 | 5.90 | 99.73 |
| 100 | 60 | Performance | 26.40 | 29.21 | 28.76 | 29.21 | 0.00 | 0.00 | 49.13 | 104.36 |
| 100 | 60 | UIImageView animationImages | 50.32 | 29.16 | 410.66 | 470.05 | 382.09 | 440.89 | 14.14 | 99.43 |
| 240 | 12 | Asset catalog | 25.42 | 29.13 | 30.82 | 30.91 | 1.69 | 1.78 | 5.68 | 64.80 |
| 240 | 12 | Performance | 34.30 | 29.17 | 28.56 | 29.17 | 0.00 | 0.00 | 20.24 | 103.58 |
| 240 | 12 | UIImageView animationImages | 163.39 | 29.22 | 563.30 | 1100.71 | 535.74 | 1071.49 | 87.05 | 105.77 |
| 240 | 24 | Asset catalog | 6.47 | 29.21 | 30.86 | 30.94 | 1.65 | 1.74 | 5.99 | 99.72 |
| 240 | 24 | Performance | 34.83 | 29.13 | 28.52 | 29.13 | 0.00 | 0.00 | 28.71 | 113.80 |
| 240 | 24 | UIImageView animationImages | 92.17 | 29.17 | 384.05 | 1100.36 | 357.06 | 1071.19 | 93.88 | 99.12 |
| 240 | 60 | Asset catalog | 5.68 | 29.17 | 30.81 | 30.89 | 1.64 | 1.72 | 6.19 | 100.13 |
| 240 | 60 | Performance | 33.41 | 29.14 | 28.53 | 29.14 | 0.00 | 0.00 | 48.17 | 113.23 |
| 240 | 60 | UIImageView animationImages | 91.92 | 29.16 | 563.30 | 1100.72 | 535.77 | 1071.56 | 97.54 | 105.25 |

## Notes

The original project, which provides a custom class rather than extending UIImageView, and is written in Objective-C, is retained on the `objc` branch.

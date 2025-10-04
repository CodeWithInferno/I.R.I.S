# LiDAR Obstacle Detection

Real-time obstacle detection app using iPhone Pro's LiDAR scanner to help users navigate their environment safely.

## Features

- **Real-time Distance Measurement**: Continuously calculates distance to obstacles in front, left, and right directions
- **Visual Warnings**: Color-coded distance indicators (green = safe, yellow = caution, orange = warning, red = critical)
- **Multi-Modal Alerts**: Haptic feedback, audio alerts, and visual warnings for nearby obstacles
- **Customizable Thresholds**: Adjust warning and critical distance thresholds in settings
- **3D Mesh Visualization**: Optional display of environment mesh and depth map
- **Scene Classification**: Identifies walls, floors, tables, and other surfaces

## Requirements

- **Device**: iPhone 12 Pro or later (requires LiDAR scanner)
- **iOS**: 15.0+
- **Xcode**: 14.0+

## Installation

1. Clone the repository
2. Open in Xcode
3. Select your development team in project settings
4. Build and run on a LiDAR-equipped device

## Usage

1. Launch the app and grant camera permissions
2. Point your device forward to scan the environment
3. The app displays real-time distances to obstacles:
   - **Front**: Distance directly ahead
   - **Left/Right**: Peripheral obstacle distances
4. Adjust settings for personalized alerts:
   - Warning threshold (default: 1.5m)
   - Critical threshold (default: 0.5m)
   - Enable/disable haptic, audio, and visual alerts

## How It Works

The app uses ARKit's scene reconstruction capabilities:

1. **LiDAR Depth Sensing**: Captures depth data at 60fps with 256x192 resolution
2. **Scene Mesh Generation**: Creates real-time 3D mesh of environment
3. **Distance Calculation**: Processes depth buffer to measure obstacle distances
4. **Alert System**: Triggers warnings based on proximity thresholds

## API Overview

### Core Components

- `ARViewModel`: Manages AR session, depth processing, and alerts
- `ContentView`: SwiftUI interface with distance displays
- `ARViewContainer`: UIViewRepresentable wrapper for ARView

### Key Methods

```swift
// Process depth data from LiDAR
processDepthData(_ depthData: ARDepthData)

// Check and trigger warnings
checkForWarnings(distance: Float)

// Haptic feedback
triggerWarningHaptic()
triggerCriticalHaptic()
```

## Settings

- **Detection Settings**:
  - Warning Distance: 0.5m - 3.0m
  - Critical Distance: 0.3m - 1.5m
- **Feedback Options**:
  - Haptic vibration
  - Audio alerts
  - Visual warnings
- **Display Options**:
  - Show 3D mesh
  - Show depth map
  - Debug information

## Privacy

The app requires camera access to use the LiDAR scanner. All processing is done locally on device. No data is collected or transmitted.

## License

MIT
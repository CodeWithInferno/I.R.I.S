# I.R.I.S - Intelligent Radar for Independent Sightless
### Turn Darkness into Direction

<img src="https://img.shields.io/badge/iOS-15.0+-blue.svg" alt="iOS 15.0+" />
<img src="https://img.shields.io/badge/Swift-5.9-orange.svg" alt="Swift 5.9" />
<img src="https://img.shields.io/badge/LiDAR-Required-green.svg" alt="LiDAR Required" />
<img src="https://img.shields.io/badge/Battery-<5%25%2Fhour-brightgreen.svg" alt="Battery Efficient" />

## 🎯 What is I.R.I.S?

I.R.I.S transforms iPhone LiDAR data into simple haptic navigation for blind users. Using morse-code patterns (dots for left, dash for right), it enables independent navigation without sight.

## 🚨 FOR JUDGES: [Click here for detailed setup instructions](./SETUP_FOR_JUDGES.md)

## ✨ Key Features

- **Simple Morse Code Navigation**: 4 dots = turn left, 1 dash = turn right
- **Real-time LiDAR Scanning**: 60Hz obstacle detection up to 5 meters
- **Battery Efficient**: <5% per hour using ARM optimization
- **VoiceOver Compatible**: Full accessibility support
- **Obstacle Memory**: Remembers frequently visited spaces
- **No Internet Required**: All processing happens on-device

## 📱 Requirements

- **Device**: iPhone 12 Pro or later (LiDAR required)
- **iOS**: 15.0 or later
- **Xcode**: 14.0 or later (for building)

## 🛠 Quick Start

1. Clone repository:
```bash
git clone https://github.com/CodeWithInferno/I.R.I.S.git
cd I.R.I.S/LiDARObstacleDetection
```

2. Open in Xcode:
```bash
open LiDARObstacleDetection.xcodeproj
```

3. Connect iPhone, select it as target, and press Run

**First time?** See [SETUP_FOR_JUDGES.md](./SETUP_FOR_JUDGES.md) for detailed instructions including trust settings.

## 🎮 How to Use

### Haptic Patterns
- **• • • •** (4 dots) = Turn LEFT
- **———** (1 dash) = Turn RIGHT
- **• •** (2 taps) = Go STRAIGHT
- **~~~~~** (continuous) = STOP

### Holding Position
- Hold phone at chest height
- Point forward like taking a photo
- Keep phone steady for best results

## 🏗 Technical Architecture

### Core Technologies
- **ARKit**: Scene reconstruction and depth API
- **LiDAR**: Real-time 3D spatial mapping
- **Core Haptics**: Custom haptic patterns
- **Core ML**: Obstacle classification
- **Metal**: GPU-accelerated processing

### Performance Optimizations
- ARM64 NEON instructions for vector math
- Neural Engine for depth processing
- Spatial hashing for efficient lookups
- Memory caching for static obstacles

## 📊 Performance Metrics

- **Latency**: <16ms response time
- **Battery**: <5% per hour
- **Range**: 0.5m - 5m detection
- **CPU**: <15% utilization
- **Memory**: ~120MB active

## 🧪 Testing

### Blindfolded Navigation Test
1. Set up obstacle course with chairs/tables
2. Put on blindfold
3. Hold phone at chest height
4. Follow haptic feedback to navigate

### Accessibility Test
1. Enable VoiceOver in iOS Settings
2. Launch app
3. Verify all UI elements are announced
4. Test navigation with screen reader active

## 🤝 Team

Built with ❤️ at hackathon by Team I.R.I.S

## 📄 License

MIT License - See [LICENSE](LICENSE) file

## 🙏 Acknowledgments

- Apple ARKit team for incredible LiDAR APIs
- Our test users who provided invaluable feedback
- Hackathon organizers and mentors

---

**For Judges**: Please see [SETUP_FOR_JUDGES.md](./SETUP_FOR_JUDGES.md) for complete setup instructions.

**For Users**: Download from TestFlight (coming soon) or build from source.
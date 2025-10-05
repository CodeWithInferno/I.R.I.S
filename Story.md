# IRIS - Turn Darkness into Direction

## Inspiration

My uncle has been blind since birth. Growing up, I watched him navigate his house by touching every wall, counting steps, memorizing exact distances. When we'd visit new places, he'd grip my shoulder while I'd try to describe everything - "there's a table coming up on your left, about three steps." But words aren't enough. You can't describe every chair leg, every corner, every low-hanging sign.

The worst part? Watching him in crowded places. People don't see the cane in time. They bump into him, he apologizes even though it's not his fault. He has to touch everything - public handrails, dirty walls, random surfaces - just to know where he is. COVID made this even scarier.

One day he asked me, "You're studying computer science, right? Why can't my phone tell me where walls are? It has all these cameras." That hit different. He was right. We have self-driving cars but blind people still use the same stick from hundreds of years ago.

## What it does

Our app uses the iPhone's LiDAR scanner (that depth sensor on the Pro models) to create a real-time 3D map of your surroundings. But here's the thing - blind people don't need a map, they need directions. So we convert that depth data into simple haptic feedback:

- **4 quick taps (dots)** = turn left
- **1 long vibration (dash)** = turn right
- **2 gentle taps** = go straight, path is clear
- **Continuous buzz** = STOP, something's too close

It scans 60 times per second, detecting obstacles up to 5 meters away. The app remembers frequently visited places, so your home and office are pre-mapped, saving battery.

## How we built it

We used ARKit's depth API to access raw LiDAR point cloud data. The mesh reconstruction happens in real-time using Scene Reconstruction. For the haptics, we implemented Core Haptics with custom morse-like patterns.

The smart part - we only scan at eye level (middle third of the screen) to avoid detecting the ground as an obstacle. This took forever to figure out. The ground kept triggering "STOP" warnings.

We built an obstacle memory system using Core ML that learns static objects (walls, furniture) vs dynamic ones (people, doors). Static stuff gets cached, reducing processing by 60%.

## Challenges we ran into

Man, where do I start? First, the ground detection issue - LiDAR sees EVERYTHING including the floor, and for three days straight, our app thought the ground was a wall. We tried filters, height maps, plane detection - nothing worked. Finally realized we could just ignore the bottom half of the scan.

The haptic feedback was overwhelming at first. It was buzzing constantly, giving feedback for every single object. We had to add minimum 2.5 second delays between feedback and prioritize only the most important directions.

Apple's restrictions were rough. You need a paid developer account to properly test on devices. We kept hitting provisioning errors. The TestFlight submission process is a nightmare without an account.

## Accomplishments that we're proud of

We tested it here at the hackathon venue blindfolded. Set up a whole obstacle course with chairs, tables, and bags scattered around. Our team member walked through the entire thing without hitting anything. Other teams stopped to watch - they couldn't believe someone could navigate blindfolded using just phone vibrations.

The battery optimization is insane - we got it from 40% per hour down to under 5%. The trick was the memory system. Once it knows a space, it stops aggressively scanning and only checks for changes. During our 24-hour hackathon coding session, one iPhone ran the whole time on a single charge.

The simplicity is what we're most proud of. Other teams doing similar projects have complex audio cues, voice commands, special gestures. Ours? Dots and dashes. That's it. We watched a volunteer learn it in literally 2 minutes and navigate successfully.

We also made it work with VoiceOver perfectly. Most apps break Apple's built-in accessibility features, but ours enhances them. Blind users don't have to choose between their screen reader and our navigation.

## What we learned

LiDAR is powerful but noisy. Raw depth data needs massive filtering to be useful. We learned about point cloud processing, RANSAC algorithms for plane detection, and spatial hashing for efficient lookups.

Accessibility isn't about adding features - it's about removing complexity. Every "cool" feature we added made it harder for actual blind users. Simple is better.

Building for blind users means testing blind. We spent hours blindfolded, walking into walls, trying to understand the experience. You can't design accessibility from the outside.

ARM architecture optimization matters. Using NEON instructions for vector math made our distance calculations 3x faster. The Neural Engine processes depth maps in 8ms vs 25ms on CPU.

## What's next for IRIS

The dream is still a $50 wristband with mini-LiDAR. We've found suppliers who can do depth sensors for $30 in bulk. Add a cheap haptic motor, Bluetooth chip, and battery - we could make something affordable.

We want to add crowd-sourced maps. Imagine if every IRIS user contributed to a shared database of obstacles. Coffee shops, malls, airports - all pre-mapped by the community.

Voice notes for specific obstacles. Like "careful, wet floor sign" or "construction ahead." Context that haptics can't provide.

Integration with smart cities. Some cities already have Bluetooth beacons for navigation. We could combine that with our LiDAR scanning for perfect accuracy.

Partnership with Guide Dogs organizations. This isn't meant to replace guide dogs but supplement them. For people on waiting lists or in areas where guide dogs aren't available.

But honestly? Right now we just want blind people to use it. To walk without fear. To stop apologizing for existing in public spaces. To have independence.

That's all we want.
import Foundation
import CoreGraphics
import AppKit

// MARK: - Themes & Settings

enum KeyboardTheme: String, CaseIterable {
    case classicMilk = "经典奶白暖黄 (原版)"
    case midnightHacker = "暗夜极客黑"
    case retroCream = "复古奶油灰"
}

enum CatCoatTheme: String, CaseIterable {
    case classicBlack = "经典小黑猫 (原版)"
    case siamese = "挖煤暹罗猫"
    case pink = "樱花小猫"
}

enum EyeColorTheme: String, CaseIterable {
    case neonChartreuse = "经典荧光黄绿 (原版)"
    case siameseBlue = "暹罗宝石蓝 (暹罗标配)"
    case warmAmber = "琥珀金瞳"
    case iceCyan = "冰晶浅蓝"

    var primaryColor: NSColor {
        switch self {
        case .neonChartreuse: return NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 1.0) // #C9F240
        case .siameseBlue:    return NSColor(calibratedRed: 0.37, green: 0.78, blue: 0.98, alpha: 1.0) // #5EC7FA
        case .warmAmber:      return NSColor(calibratedRed: 0.98, green: 0.76, blue: 0.22, alpha: 1.0)
        case .iceCyan:        return NSColor(calibratedRed: 0.45, green: 0.92, blue: 0.96, alpha: 1.0)
        }
    }

    var glowColor: NSColor {
        switch self {
        case .neonChartreuse: return NSColor(calibratedRed: 0.77, green: 0.95, blue: 0.24, alpha: 0.85)
        case .siameseBlue:    return NSColor(calibratedRed: 0.38, green: 0.80, blue: 0.99, alpha: 0.85)
        case .warmAmber:      return NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.20, alpha: 0.85)
        case .iceCyan:        return NSColor(calibratedRed: 0.42, green: 0.90, blue: 0.98, alpha: 0.85)
        }
    }
}

final class CatSettings {
    static let shared = CatSettings()

    var showKeyBadges: Bool {
        didSet { UserDefaults.standard.set(showKeyBadges, forKey: "KuroCat.ShowKeyBadges") }
    }
    var footEasterEgg: Bool {
        didSet { UserDefaults.standard.set(footEasterEgg, forKey: "KuroCat.FootEasterEgg") }
    }
    var petInteraction: Bool {
        didSet { UserDefaults.standard.set(petInteraction, forKey: "KuroCat.PetInteraction") }
    }
    var fullClickThrough: Bool {
        didSet { UserDefaults.standard.set(fullClickThrough, forKey: "KuroCat.FullClickThrough") }
    }
    var fullScreenOverlay: Bool {
        didSet { UserDefaults.standard.set(fullScreenOverlay, forKey: "KuroCat.FullScreenOverlay") }
    }
    var scale: CGFloat {
        didSet { UserDefaults.standard.set(Double(scale), forKey: "KuroCat.Scale") }
    }
    var coatTheme: CatCoatTheme {
        didSet { UserDefaults.standard.set(coatTheme.rawValue, forKey: "KuroCat.CoatTheme") }
    }
    var keyboardTheme: KeyboardTheme {
        didSet { UserDefaults.standard.set(keyboardTheme.rawValue, forKey: "KuroCat.KeyboardTheme") }
    }
    var eyeTheme: EyeColorTheme {
        didSet { UserDefaults.standard.set(eyeTheme.rawValue, forKey: "KuroCat.EyeTheme") }
    }

    private init() {
        let d = UserDefaults.standard
        showKeyBadges = d.object(forKey: "KuroCat.ShowKeyBadges") as? Bool ?? true
        footEasterEgg = d.object(forKey: "KuroCat.FootEasterEgg") as? Bool ?? true
        petInteraction = d.object(forKey: "KuroCat.PetInteraction") as? Bool ?? true
        fullClickThrough = d.object(forKey: "KuroCat.FullClickThrough") as? Bool ?? false
        fullScreenOverlay = d.object(forKey: "KuroCat.FullScreenOverlay") as? Bool ?? true
        let savedScale = d.double(forKey: "KuroCat.Scale")
        scale = savedScale > 0.3 ? CGFloat(savedScale) : 1.0
        coatTheme = CatCoatTheme(rawValue: d.string(forKey: "KuroCat.CoatTheme") ?? "") ?? .classicBlack
        keyboardTheme = KeyboardTheme(rawValue: d.string(forKey: "KuroCat.KeyboardTheme") ?? "") ?? .classicMilk
        eyeTheme = EyeColorTheme(rawValue: d.string(forKey: "KuroCat.EyeTheme") ?? "") ?? .neonChartreuse
    }
}

// MARK: - Spring Primitives

struct Spring1D {
    var value: CGFloat
    var velocity: CGFloat = 0
    var target: CGFloat

    init(_ initial: CGFloat) {
        self.value = initial
        self.target = initial
    }

    mutating func step(dt: CGFloat, stiffness: CGFloat = 260, damping: CGFloat = 22) {
        let force = (target - value) * stiffness
        let damp = velocity * damping
        velocity += (force - damp) * dt
        value += velocity * dt
    }
}

struct Spring2D {
    var x: Spring1D
    var y: Spring1D

    init(_ pt: CGPoint) {
        self.x = Spring1D(pt.x)
        self.y = Spring1D(pt.y)
    }

    var point: CGPoint { CGPoint(x: x.value, y: y.value) }
    var target: CGPoint {
        get { CGPoint(x: x.target, y: y.target) }
        set { x.target = newValue.x; y.target = newValue.y }
    }

    mutating func step(dt: CGFloat, stiffness: CGFloat = 340, damping: CGFloat = 25) {
        x.step(dt: dt, stiffness: stiffness, damping: damping)
        y.step(dt: dt, stiffness: stiffness, damping: damping)
    }
}

// MARK: - Particles

struct FloatingKeycap {
    let id: Int
    let label: String
    var position: CGPoint
    var velocity: CGPoint
    var age: CGFloat = 0
    let lifetime: CGFloat = 1.25
    var rotation: CGFloat
}

struct PurrSparkle {
    var position: CGPoint
    var velocity: CGPoint
    var age: CGFloat = 0
    let lifetime: CGFloat = 0.9
    let isSleepZ: Bool
}

/// Music-note particle floating up with the beat. Styled after the existing keycaps/sparkles.
struct MusicNoteParticle {
    var position: CGPoint
    var velocity: CGPoint
    var age: CGFloat = 0
    let lifetime: CGFloat
    let glyph: Int          // index into musical note glyph set
    let rotation: CGFloat
    let scale: CGFloat
}

/// Soft smoke wisp rising from the head when the cat is mentally fried from typing too fast.
struct SmokePuff {
    var position: CGPoint
    var velocity: CGPoint
    var age: CGFloat = 0
    let lifetime: CGFloat
    let radius: CGFloat
    let seed: CGFloat
}

struct ScriptedFrameInput {
    var now: CFTimeInterval
    var activeKeys: Set<PhysicalKey>
    var orderedKeys: [PhysicalKey]
    var mouseScreenPos: CGPoint
    var mouseVelocity: CGVector
    var leftMouseDown: Bool
    var rightMouseDown: Bool
    var lastMouseMoveTime: CFTimeInterval
    var lastMouseClickTime: CFTimeInterval
    var lastKeyActivityTime: CFTimeInterval
}

// MARK: - Cat Physics & Procedural Animation State

final class CatPhysics {
    // Logical canvas dimensions
    static let canvasSize = CGSize(width: 360, height: 320)

    // Rest positions
    static let seatAnchor = CGPoint(x: 184, y: 226)
    static let leftPawRest = CGPoint(x: 164, y: 235)
    static let rightPawRest = CGPoint(x: 204, y: 235)
    static let hindFootRest = CGPoint(x: 214, y: 234)
    static let mouseBaseCenter = CGPoint(x: 78, y: 258)

    // Springs
    var leftPaw = Spring2D(leftPawRest)
    var rightPaw = Spring2D(rightPawRest)
    var hindFoot = Spring2D(hindFootRest)
    var hindFootActive = Spring1D(0) // 0 = tucked, 1 = kicking 3rd key

    var bodyShiftX = Spring1D(0)
    var bodyTilt = Spring1D(0)       // radians
    var bodySquash = Spring1D(1.0)
    var headTilt = Spring1D(0)       // radians (roll)
    var headYaw = Spring1D(0)        // -1 (turn left) ... +1 (turn right)
    var headPitch = Spring1D(0)      // -1 (look up)   ... +1 (look down)
    var headOffsetY = Spring1D(0)
    var earFold = Spring1D(0)        // 0 = alert, 1 = relaxed petting ears
    var earTwitch = Spring1D(0)

    var eyeGaze = Spring2D(.zero)    // normalized [-1..1, -1..1]
    var pupilScale = Spring1D(1.0)
    var huntIntensity = Spring1D(0)  // 0 = normal slit pupils, 1 = full hunting crouch + big round boba pupils!
    var mouseOffset = Spring2D(.zero)
    var mousePressLeft = Spring1D(0)
    var mousePressRight = Spring1D(0)

    // Paw mode flags (for crisp outline & posture rendering)
    private(set) var leftPawOnMouse = false
    private(set) var leftPawTyping = false
    private(set) var rightPawTyping = false

    // Keycap glow & press depths
    var keyGlow: [PhysicalKey: CGFloat] = [:]
    var floatingKeycaps: [FloatingKeycap] = []
    var sparkles: [PurrSparkle] = []
    var musicNotes: [MusicNoteParticle] = []
    private var nextBadgeID = 1
    private var badgeCascadeIndex = 0
    private var lastBadgeTime: CFTimeInterval = 0

    // MARK: - Music mode state (overlay only — never suppresses typing animations)
    var equalizerPresence: CGFloat = 0        // 0...1 fade-in of the mic/spectrum bars
    var musicBounce: CGFloat = 0              // spring-ish head bob driven by bass
    var musicBlinkBoost: CGFloat = 0          // subtle happy-eye squint on beats
    private var lastNoteTime: CFTimeInterval = 0
    private var noteGlyphIndex = 0

    // MARK: - Overload easter egg (typing too fast -> strain -> 3s fried/dazed with smoke)
    // Strain builds from a short rolling keystroke window; when it peaks and typing stops,
    // the cat "short-circuits": dazed spiraled eyes + smoke for 3s, until a key or mouse move.
    private var keyTimes: [CFTimeInterval] = []
    private var fastStreakStart: CFTimeInterval = 0 // when the current fast burst began
    private var lastFastKeyTime: CFTimeInterval = 0
    private var overloadArmed = false               // a genuine fast-typing burst happened
    private(set) var strain: CGFloat = 0            // 0..1 effort/straining face while typing fast
    private(set) var isFried = false                // dazed + smoke state active
    private(set) var friedTimeLeft: CGFloat = 0     // counts down from 3.0
    private var friedStartedAt: CFTimeInterval = 0
    private var smokeCooldown: CGFloat = 0
    private(set) var smokePuffs: [SmokePuff] = []

    // Time & blink
    private(set) var time: CGFloat = 0
    private(set) var tailPhase: CGFloat = 0
    private var nextBlinkTime: CGFloat = 3.2
    private var blinkProgress: CGFloat = 0 // 0 = open, 1 = closed
    private var isBlinking = false
    private var blinkTimer: CGFloat = 0

    // Petting state
    private(set) var petHeadIntensity: CGFloat = 0  // 0..1 -> happy closed lime lines
    private(set) var petBodyIntensity: CGFloat = 0  // 0..1 -> blissful half-squint
    private(set) var totalPetSessions: Int = UserDefaults.standard.integer(forKey: "KuroCat.PetCount")
    private var petStrokeAccumulator: CGFloat = 0
    private var lastPetTime: CFTimeInterval = 0
    private var isCurrentlyPetting = false
    private var petCursorCanvasPos: CGPoint = .zero
    private var petSparkleCooldown: CGFloat = 0

    // Sleepy idle state
    private(set) var sleepiness: CGFloat = 0 // 0 = awake, 1 = napping
    private var sleepZCooldown: CGFloat = 0

    // Recent key memory so fast single taps linger visibly (~140ms)
    private var recentLeftKey: (key: PhysicalKey, time: CFTimeInterval)?
    private var recentRightKey: (key: PhysicalKey, time: CFTimeInterval)?
    private var lastTypedPoint: CGPoint?

    // Computed eye closure (0 = wide open, 0.55 = half squint, 1 = fully closed)
    var effectiveEyeClosure: CGFloat {
        let petClose = max(petHeadIntensity * 1.0, petBodyIntensity * 0.62)
        let sleepClose = sleepiness * 0.92
        // Music beat adds a tiny delighted squint — subtle, never fully closes
        let musicClose = musicBlinkBoost * 0.52
        return min(1.0, max(blinkProgress, max(petClose, max(sleepClose, musicClose))))
    }

    /// True when eyes should draw the signature glowing lime horizontal closed-eye lines
    var isHappyClosedEyes: Bool {
        petHeadIntensity > 0.45
    }

    var isBlissfulSquint: Bool {
        petBodyIntensity > 0.35 && !isHappyClosedEyes
    }

    /// Effort face: typing furiously — furrowed brow, narrowed determined eyes, gritted teeth.
    var isStraining: Bool {
        strain > 0.42 && !isFried && !isHappyClosedEyes
    }

    /// Three escalating effort tiers while straining:
    /// 1 = slightly exerting, 2 = really trying, 3 = all-out / about to explode.
    /// 0 when not straining. Thresholds sit inside the straining strain band (0.42...1.0).
    var strainTier: Int {
        guard isStraining else { return 0 }
        if strain < 0.64 { return 1 }
        if strain < 0.85 { return 2 }
        return 3
    }

    /// Dazed/fried face takes priority over every other expression and over music notes.
    var isDazed: Bool { isFried }

    // MARK: - Input Hooks

    func triggerKeyDown(_ key: PhysicalKey, at timestamp: CFTimeInterval? = nil) {
        let now = timestamp ?? CACurrentMediaTime()
        let vk = key.visualKey
        keyGlow[vk] = 1.0

        // Any fresh keystroke snaps the cat out of the dazed/fried state.
        if isFried { endFried(now: now) }

        // Feed the short rolling window used to measure typing speed.
        keyTimes.append(now)
        if keyTimes.count > 64 { keyTimes.removeFirst(keyTimes.count - 64) }

        let pt = KeyboardLayout.canvasPoint(for: vk)
        lastTypedPoint = pt

        // Snap memory to the appropriate paw with lively bounce velocity
        let active = InputEngine.shared.activeKeys
        let leftHeld = active.contains { $0.prefersLeftPaw }
        let rightHeld = active.contains { !$0.prefersLeftPaw }

        if key.prefersLeftPaw {
            recentLeftKey = (vk, now)
            leftPaw.y.velocity -= 180
        } else if !rightHeld || !leftHeld {
            recentRightKey = (vk, now)
            rightPaw.y.velocity -= 180
        } else {
            recentRightKey = (vk, now)
            rightPaw.y.velocity -= 180
        }

        // Expressive micro-reactions
        bodySquash.velocity -= 1.3
        earTwitch.velocity += (key.prefersLeftPaw ? -3.8 : 3.8)
        headTilt.velocity += (key.prefersLeftPaw ? -1.4 : 1.4)
        pupilScale.target = 1.16

        // Wake up immediately
        sleepiness = 0

        // Spawn floating keycap badge
        if CatSettings.shared.showKeyBadges {
            spawnFloatingKeycap(label: key.badgeLabel, near: pt, now: now)
        }
    }

    func triggerMouseClick(button: Int, isDown: Bool) {
        sleepiness = 0
        if isDown {
            if button == 0 {
                mousePressLeft.target = 1.0
                leftPaw.y.velocity += 130
            } else {
                mousePressRight.target = 1.0
                leftPaw.y.velocity += 110
            }
            pupilScale.target = 1.12
            earTwitch.velocity -= 2.2
        } else {
            if button == 0 { mousePressLeft.target = 0 }
            else { mousePressRight.target = 0 }
        }
    }

    /// Called by the overlay window when cursor strokes across the cat's head or body.
    func registerPetStroke(canvasPoint: CGPoint, delta: CGFloat, isHead: Bool, at timestamp: CFTimeInterval? = nil) {
        guard CatSettings.shared.petInteraction else { return }
        let now = timestamp ?? CACurrentMediaTime()
        lastPetTime = now
        petCursorCanvasPos = canvasPoint
        sleepiness = 0

        let energy = min(delta / 26.0, 0.35)
        if isHead {
            petHeadIntensity = min(1.0, petHeadIntensity + energy + 0.08)
            petBodyIntensity = max(petBodyIntensity, petHeadIntensity * 0.6)
        } else {
            petBodyIntensity = min(1.0, petBodyIntensity + energy + 0.07)
        }

        petStrokeAccumulator += delta
        if !isCurrentlyPetting && petStrokeAccumulator > 45 {
            isCurrentlyPetting = true
            totalPetSessions += 1
            UserDefaults.standard.set(totalPetSessions, forKey: "KuroCat.PetCount")
        }

        // Gentle nuzzle toward cursor
        let dx = (canvasPoint.x - CatPhysics.seatAnchor.x) / 60.0
        headTilt.target = max(-0.18, min(0.18, dx * 0.16))
        headOffsetY.velocity += 18
    }

    private func spawnFloatingKeycap(label: String, near pt: CGPoint, now: CFTimeInterval) {
        if now - lastBadgeTime < 0.38 {
            badgeCascadeIndex = (badgeCascadeIndex + 1) % 6
        } else {
            badgeCascadeIndex = 0
        }
        lastBadgeTime = now

        // Spread fast bursts gracefully so they stay readable like "F O J F E A"
        let spreadOffsets: [CGFloat] = [-10, 14, -22, 26, 2, 36]
        let dx = spreadOffsets[badgeCascadeIndex] + CGFloat.random(in: -3...3)
        let startX = max(55, min(315, pt.x + dx * 0.45))
        let startY = pt.y - 26 - CGFloat(badgeCascadeIndex % 2) * 8

        let badge = FloatingKeycap(
            id: nextBadgeID,
            label: label,
            position: CGPoint(x: startX, y: startY),
            velocity: CGPoint(x: dx * 0.65, y: -36 - CGFloat.random(in: 0...14)),
            rotation: CGFloat.random(in: -0.07...0.07)
        )
        nextBadgeID += 1
        floatingKeycaps.append(badge)
        if floatingKeycaps.count > 16 {
            floatingKeycaps.removeFirst(floatingKeycaps.count - 16)
        }
    }

    // MARK: - 60 FPS Simulation Step

    func step(dt rawDt: CGFloat, windowFrameInScreen: CGRect, scripted: ScriptedFrameInput? = nil) {
        let dt = min(rawDt, 1.0 / 25.0)
        time += dt

        let engine = InputEngine.shared
        if scripted == nil {
            engine.pollMouse(dt: dt)
        }

        let now = scripted?.now ?? CACurrentMediaTime()
        let activeKeys = scripted?.activeKeys ?? engine.activeKeys
        let orderedKeys = scripted?.orderedKeys ?? engine.pressedOrder
        let curMouseVel = scripted?.mouseVelocity ?? engine.mouseVelocity
        let curMouseLoc = scripted?.mouseScreenPos ?? engine.lastMouseLocation
        let curLeftMouse = scripted?.leftMouseDown ?? engine.leftMouseDown
        let curRightMouse = scripted?.rightMouseDown ?? engine.rightMouseDown
        let curLastMouseMove = scripted?.lastMouseMoveTime ?? engine.lastMouseMoveTime
        let curLastMouseClick = scripted?.lastMouseClickTime ?? engine.lastMouseClickTime
        let curLastKeyTime = scripted?.lastKeyActivityTime ?? engine.lastKeyActivityTime

        // 2a. Fast-typing overload state machine.
        // A 1.8s window plus a sustained-fast requirement keeps casual typing from
        // looking like a furious burst. Strain grows only after ~0.85s of >8 keys/s,
        // and scales steeply with speed so ordinary chatter stays neutral.
        keyTimes.removeAll { now - $0 > 1.8 }
        let rate = CGFloat(keyTimes.count) / 1.8
        let activelyTyping = curLastKeyTime > 0 && (now - curLastKeyTime) < 0.35
        let fastEnough = activelyTyping && rate >= 8.0
        if fastEnough {
            if fastStreakStart == 0 { fastStreakStart = now }
        } else {
            fastStreakStart = 0
        }
        let sustainedFast = fastEnough && (now - fastStreakStart) >= 0.85
        let normalized = max(0, min(1, (rate - 7.0) / 5.0))
        let strainTarget = sustainedFast ? pow(normalized, 1.4) : 0
        let strainRate: CGFloat = strainTarget > strain ? 5.5 : 3.2
        strain += (strainTarget - strain) * min(1, dt * strainRate)

        // Only a genuinely sustained burst arms the fried/overload trigger.
        let fastTyping = sustainedFast && rate >= 10.0 && (now - curLastKeyTime) < 0.12
        if fastTyping {
            lastFastKeyTime = now
            overloadArmed = true
        }

        if isFried {
            // Fried ends on its 3s timer, on any fresh key (handled in triggerKeyDown),
            // or on a deliberate mouse move.
            friedTimeLeft -= dt
            let moveSpeed = hypot(curMouseVel.dx, curMouseVel.dy)
            if friedTimeLeft <= 0 || (moveSpeed > 55 && now - curLastMouseMove < 0.25) {
                endFried(now: now)
            }
        } else {
            // The instant an armed fast burst truly goes quiet (no new keys) -> short-circuit.
            let noKeyFor = curLastKeyTime > 0 ? (now - curLastKeyTime) : .infinity
            let sinceFast = lastFastKeyTime > 0 ? (now - lastFastKeyTime) : .infinity
            if overloadArmed && noKeyFor > 0.16 && sinceFast > 0.12 && sinceFast < 0.85 {
                startFried(now: now)
            }
            // If the burst ended long ago without a clean pause, disarm so an idle
            // period (or a later slow session) can never trigger it.
            if sinceFast > 2.5 { overloadArmed = false }
        }

        // 1. Decay petting intensity gracefully when hand stops moving
        if now - lastPetTime > 0.28 {
            petHeadIntensity = max(0, petHeadIntensity - dt * 1.4)
            petBodyIntensity = max(0, petBodyIntensity - dt * 1.2)
            if petHeadIntensity < 0.05 && petBodyIntensity < 0.05 {
                isCurrentlyPetting = false
                petStrokeAccumulator = 0
            }
        } else if (petHeadIntensity > 0.55 || petBodyIntensity > 0.55) {
            petSparkleCooldown -= dt
            if petSparkleCooldown <= 0 {
                petSparkleCooldown = 0.42
                let sx = CatPhysics.seatAnchor.x + CGFloat.random(in: -44...44)
                let sy = 88 + CGFloat.random(in: -14...18)
                sparkles.append(PurrSparkle(
                    position: CGPoint(x: sx, y: sy),
                    velocity: CGPoint(x: CGFloat.random(in: -10...10), y: -24),
                    isSleepZ: false
                ))
            }
        }

        // 2. Sleepy idle detection
        let lastAnyActivity = max(curLastKeyTime, max(curLastMouseMove, lastPetTime))
        let idleSeconds = lastAnyActivity > 0 ? (now - lastAnyActivity) : 0
        if activeKeys.isEmpty && idleSeconds > 45 {
            let targetSleep = min(1.0, CGFloat((idleSeconds - 45) / 35.0))
            sleepiness += (targetSleep - sleepiness) * dt * 1.5
            if sleepiness > 0.8 {
                sleepZCooldown -= dt
                if sleepZCooldown <= 0 {
                    sleepZCooldown = 2.6
                    sparkles.append(PurrSparkle(
                        position: CGPoint(x: CatPhysics.seatAnchor.x + 42, y: 100),
                        velocity: CGPoint(x: 12, y: -18),
                        isSleepZ: true
                    ))
                }
            }
        } else {
            sleepiness = max(0, sleepiness - dt * 5.0)
        }

        // 2b. Fast Mouse Movement -> Hunting / Stalking Mode (dilated round boba pupils + low crouch!)
        let mouseSpeed = hypot(curMouseVel.dx, curMouseVel.dy)
        if mouseSpeed > 460 && petHeadIntensity < 0.25 && petBodyIntensity < 0.25 {
            // Build up smoothly & responsively with fast mouse waving (laser-pointer effect!)
            let boost = min(1.0, (mouseSpeed - 460) / 1100.0)
            huntIntensity.target = min(1.0, huntIntensity.target + (0.45 + boost * 1.15) * dt)
            sleepiness = 0
        } else {
            // Calm down gently once cursor stops darting
            huntIntensity.target = max(0.0, huntIntensity.target - dt * 0.65)
        }
        huntIntensity.step(dt: dt, stiffness: 85, damping: 16)
        let hunt = max(0, min(1, huntIntensity.value))

        // 3. Determine limb targets (Left Paw, Right Paw, 3rd-Key Hind Foot!)
        let tapHoldWindow: CFTimeInterval = 0.14
        let mouseRecent = (now - curLastMouseMove < 2.2) || curLeftMouse || curRightMouse
        let mouseActivelyUsed = (now - curLastMouseMove < 0.75) || curLeftMouse || curRightMouse

        // Partition active keys
        var leftCandidates: [PhysicalKey] = []
        var rightCandidates: [PhysicalKey] = []
        for k in orderedKeys {
            if k.prefersLeftPaw { leftCandidates.append(k) }
            else { rightCandidates.append(k) }
        }

        var leftKey: PhysicalKey? = leftCandidates.last
        var rightKey: PhysicalKey? = rightCandidates.last
        var footKey: PhysicalKey? = nil

        // If 2+ keys are pressed on the same side, let the free paw help —
        // UNLESS viewer-left paw (cat's right hand) is actively driving the mouse!
        if leftKey == nil && rightCandidates.count >= 2 && !mouseActivelyUsed {
            let sorted = rightCandidates.sorted {
                KeyboardLayout.canvasPoint(for: $0).x < KeyboardLayout.canvasPoint(for: $1).x
            }
            leftKey = sorted.first
            rightKey = sorted.last
        } else if rightKey == nil && leftCandidates.count >= 2 {
            let sorted = leftCandidates.sorted {
                KeyboardLayout.canvasPoint(for: $0).x < KeyboardLayout.canvasPoint(for: $1).x
            }
            leftKey = sorted.first
            rightKey = sorted.last
        }

        // 3+ simultaneous keys (or 2+ keys while other hand is busy on the mouse!) -> HIND FOOT EASTER EGG!!
        if CatSettings.shared.footEasterEgg {
            if orderedKeys.count >= 3 {
                footKey = orderedKeys.first { $0 != leftKey && $0 != rightKey }
            } else if mouseActivelyUsed && leftKey == nil && rightCandidates.count >= 2 {
                footKey = rightCandidates.first { $0 != rightKey }
            }
        }

        // Keep quick taps visible for a tiny snappy window
        if leftKey == nil, let rec = recentLeftKey, now - rec.time < tapHoldWindow {
            leftKey = rec.key
        }
        if rightKey == nil, let rec = recentRightKey, now - rec.time < tapHoldWindow {
            rightKey = rec.key
        }

        // Subtle mini-mouse movement driven by global cursor velocity
        let targetMouseDx = max(-5.5, min(5.5, curMouseVel.dx * 0.0045))
        let targetMouseDy = max(-4.5, min(4.5, -curMouseVel.dy * 0.0045))
        mouseOffset.target = CGPoint(x: targetMouseDx, y: targetMouseDy)
        mouseOffset.step(dt: dt, stiffness: 120, damping: 16)
        mousePressLeft.step(dt: dt, stiffness: 400, damping: 24)
        mousePressRight.step(dt: dt, stiffness: 400, damping: 24)

        let liveMouseCenter = CGPoint(
            x: CatPhysics.mouseBaseCenter.x + mouseOffset.point.x,
            y: CatPhysics.mouseBaseCenter.y + mouseOffset.point.y
        )

        // Paws always keep their normal typing / mouse behaviour in music mode.
        // This flag only drives the head, ears and tail groove — never the paws.
        let musicPulse = MusicPulse.shared
        let musicModeOn = (UserDefaults.standard.object(forKey: "KuroCat.MusicMode") as? Bool ?? false)
        let musicGrooveActive = musicModeOn && musicPulse.isPlaying && scripted == nil
            && leftKey == nil && rightKey == nil && !mouseRecent && sleepiness < 0.3

        // Left paw target
        if let lk = leftKey {
            leftPaw.target = KeyboardLayout.canvasPoint(for: lk)
            leftPawTyping = true
            leftPawOnMouse = false
        } else if mouseRecent && sleepiness < 0.3 {
            leftPaw.target = CGPoint(x: liveMouseCenter.x + 2, y: liveMouseCenter.y - 3)
            leftPawTyping = false
            leftPawOnMouse = true
        } else {
            leftPaw.target = CatPhysics.leftPawRest
            leftPawTyping = false
            leftPawOnMouse = false
        }

        // Right paw target
        if let rk = rightKey {
            rightPaw.target = KeyboardLayout.canvasPoint(for: rk)
            rightPawTyping = true
        } else {
            rightPaw.target = CatPhysics.rightPawRest
            rightPawTyping = false
        }

        // Hind foot target (3rd simultaneous key!)
        if let fk = footKey {
            hindFoot.target = KeyboardLayout.canvasPoint(for: fk)
            hindFootActive.target = 1.0
        } else {
            hindFoot.target = CatPhysics.hindFootRest
            hindFootActive.target = 0.0
        }

        leftPaw.step(dt: dt, stiffness: 360, damping: 24)
        rightPaw.step(dt: dt, stiffness: 360, damping: 24)
        hindFoot.step(dt: dt, stiffness: 320, damping: 22)
        hindFootActive.step(dt: dt, stiffness: 260, damping: 22)

        // 4. Expressive body lean, squash, head & ears
        var targetShiftX: CGFloat = 0
        var targetBodyTilt: CGFloat = 0
        if leftPawOnMouse && !rightPawTyping {
            targetShiftX = -10
            targetBodyTilt = -0.075
        } else if leftPawOnMouse && rightPawTyping {
            targetShiftX = -3
            targetBodyTilt = (rightPaw.point.x - 196) * 0.0008
        } else if leftPawTyping || rightPawTyping {
            let avgX = ((leftPawTyping ? leftPaw.point.x : 184) + (rightPawTyping ? rightPaw.point.x : 184)) * 0.5
            targetShiftX = (avgX - 184) * 0.14
            targetBodyTilt = (avgX - 184) * 0.0011
        }
        bodyShiftX.target = max(-16, min(16, targetShiftX))
        bodyTilt.target = max(-0.12, min(0.12, targetBodyTilt))
        // Coiled low hunting crouch when chasing a fast-moving mouse!
        bodySquash.target = 1.0 - hunt * 0.11

        headOffsetY.target = (leftPawTyping || rightPawTyping) ? 3.5 : (sleepiness * 5.0 + hunt * 10.5)
        earFold.target = max(petHeadIntensity * 0.7, petBodyIntensity * 0.45) + sleepiness * 0.25 - hunt * 0.18
        earTwitch.target = 0

        // Overload posture: straining = tense crouch; fried = head hangs, ears droop, body deflates.
        if isStraining {
            earTwitch.target = sin(now * 26) * strain * 1.5
            headOffsetY.target += strain * 2.0
        }
        if isFried {
            let droop = min(1, (3.0 - friedTimeLeft) * 2.5)
            headOffsetY.target += 7.0 * droop
            earFold.target = max(earFold.target, 0.75 * droop)
            bodySquash.target = 1.0 - 0.07 * droop
        }

        // Music: ears twitch with each real beat (both paws free).
        if musicGrooveActive {
            earTwitch.target = sin(now * 3.2) * (0.6 + musicPulse.level * 2.2) + musicPulse.beat * 3.0
        }

        bodyShiftX.step(dt: dt, stiffness: 140, damping: 18)
        bodyTilt.step(dt: dt, stiffness: 140, damping: 18)
        bodySquash.step(dt: dt, stiffness: 280, damping: 18)
        headOffsetY.step(dt: dt, stiffness: 180, damping: 19)
        earFold.step(dt: dt, stiffness: 120, damping: 16)
        earTwitch.step(dt: dt, stiffness: 320, damping: 16)

        // 5. 2.5D Head Turning (Yaw + Pitch) + Eye Tracking!
        // Head smoothly turns in pseudo-3D toward the mouse cursor (or subtly nods down toward keys while typing).
        let typingRecently = !activeKeys.isEmpty || (now - curLastKeyTime < 0.65)
        let mouseMovedRecently = (now - curLastMouseMove < 1.2)
        let eyeOriginCanvas = CGPoint(x: CatPhysics.seatAnchor.x + bodyShiftX.value, y: 124 + headOffsetY.value)

        // Compute normalized vector from cat head to real macOS screen cursor
        let scale = max(0.2, windowFrameInScreen.width / CatPhysics.canvasSize.width)
        let headScreenX = windowFrameInScreen.minX + eyeOriginCanvas.x * scale
        let headScreenY = windowFrameInScreen.maxY - eyeOriginCanvas.y * scale
        let cursor = curMouseLoc
        let curDx = (cursor.x - headScreenX) / 290.0
        let curDy = -(cursor.y - headScreenY) / 260.0
        let curMag = hypot(curDx, curDy)
        let clampedCur = min(1.0, curMag)
        let cursorNX = curMag > 0.001 ? (curDx / curMag) * clampedCur : 0
        let cursorNY = curMag > 0.001 ? (curDy / curMag) * clampedCur : 0

        let lookTargetX: CGFloat
        let lookTargetY: CGFloat
        if typingRecently && !mouseMovedRecently, let keyPt = lastTypedPoint {
            let kdx = max(-0.85, min(0.85, (keyPt.x - eyeOriginCanvas.x) / 95.0))
            let kdy = max(-0.3, min(0.92, (keyPt.y - eyeOriginCanvas.y) / 125.0))
            lookTargetX = kdx
            lookTargetY = kdy
        } else if typingRecently && mouseMovedRecently, let keyPt = lastTypedPoint {
            // Blend mouse & typing naturally when gaming with mouse + keyboard!
            let kdx = max(-0.85, min(0.85, (keyPt.x - eyeOriginCanvas.x) / 95.0))
            lookTargetX = cursorNX * 0.72 + kdx * 0.28
            lookTargetY = cursorNY * 0.72 + 0.25
        } else {
            lookTargetX = cursorNX
            lookTargetY = cursorNY
        }

        // Head turns smoothly in 2.5D (yaw & pitch) — locks on faster during hunting mode!
        if sleepiness > 0.45 {
            headYaw.target = 0
            headPitch.target = 0.45 * sleepiness
        } else {
            headYaw.target = max(-1.0, min(1.0, lookTargetX))
            headPitch.target = max(-1.0, min(1.0, lookTargetY))
        }
        // Music nod is applied after the look-at targets so it isn't overwritten.
        if musicGrooveActive {
            headPitch.target += musicPulse.beat * 0.16 + musicPulse.level * 0.04
        }
        // Fried overrides everything: head hangs down, gaze unfocused.
        if isFried {
            let droop = min(1, (3.0 - friedTimeLeft) * 2.5)
            headPitch.target = 0.32 * droop
            headYaw.target *= (1 - 0.6 * droop)
        }

        let headStiff: CGFloat = 88 + hunt * 75
        let headDamp: CGFloat = 14.5 + hunt * 4.5
        headYaw.step(dt: dt, stiffness: headStiff, damping: headDamp)
        headPitch.step(dt: dt, stiffness: headStiff, damping: headDamp)

        // Subtle natural head roll coupled to head turning (curious tilt / locked-on hunt!)
        if now - lastPetTime > 0.28 {
            headTilt.target = bodyTilt.target * 0.45 + headYaw.value * (0.11 + hunt * 0.05) - headYaw.value * headPitch.value * 0.04
        }
        if musicGrooveActive {
            headTilt.target += sin(now * 1.9) * musicPulse.level * 0.16 + musicPulse.beat * 0.12
        }
        headTilt.step(dt: dt, stiffness: 130, damping: 16)

        // Eyes lead slightly ahead of the 2.5D head turn
        eyeGaze.target = CGPoint(x: lookTargetX * 0.88, y: lookTargetY * 0.85)
        eyeGaze.step(dt: dt, stiffness: 210 + hunt * 80, damping: 21)

        // Pupil dilation
        if hindFootActive.value > 0.3 {
            pupilScale.target = 1.24
        } else if now - curLastKeyTime > 0.45 && now - curLastMouseClick > 0.45 {
            pupilScale.target = 1.0
        }
        pupilScale.step(dt: dt, stiffness: 150, damping: 18)

        // 6. Blinking (cats lock eyes without blinking during hunting mode!)
        if isBlinking {
            blinkTimer += dt
            let blinkDuration: CGFloat = 0.14
            if blinkTimer >= blinkDuration {
                isBlinking = false
                blinkProgress = 0
                nextBlinkTime = time + CGFloat.random(in: 2.6...5.6)
            } else {
                let p = blinkTimer / blinkDuration
                blinkProgress = sin(p * .pi)
            }
        } else if time >= nextBlinkTime && sleepiness < 0.5 && petHeadIntensity < 0.3 && hunt < 0.35 {
            isBlinking = true
            blinkTimer = 0
        }

        // 7. Tail wag speed reacts organically to energy / petting / hunting tension!
        let kpmBoost = min(2.4, CGFloat(engine.currentKPM) / 160.0)
        let petBoost = max(petHeadIntensity, petBodyIntensity) * 1.4
        let huntBoost = hunt * 2.8
        let musicBoost = (musicModeOn && musicPulse.isPlaying) ? musicPulse.level * 2.2 + musicPulse.beat * 1.5 : 0
        let tailSpeed: CGFloat = 1.85 + kpmBoost + petBoost + huntBoost + musicBoost - sleepiness * 1.1
        tailPhase += dt * tailSpeed

        // 8. Update per-keycap glows
        let visualActive = Set(activeKeys.map { $0.visualKey })
        for (k, v) in keyGlow {
            if visualActive.contains(k) {
                keyGlow[k] = 1.0
            } else {
                let next = v - dt * 4.5
                if next <= 0.01 { keyGlow.removeValue(forKey: k) }
                else { keyGlow[k] = next }
            }
        }
        for vk in visualActive {
            keyGlow[vk] = 1.0
        }

        // 9. Update floating keycaps
        for i in floatingKeycaps.indices.reversed() {
            floatingKeycaps[i].age += dt
            floatingKeycaps[i].position.x += floatingKeycaps[i].velocity.x * dt
            floatingKeycaps[i].position.y += floatingKeycaps[i].velocity.y * dt
            floatingKeycaps[i].velocity.x *= (1.0 - dt * 2.4)
            floatingKeycaps[i].velocity.y *= (1.0 - dt * 1.6)
            if floatingKeycaps[i].age >= floatingKeycaps[i].lifetime {
                floatingKeycaps.remove(at: i)
            }
        }

        // 10. Update purr / sleep particles
        for i in sparkles.indices.reversed() {
            sparkles[i].age += dt
            sparkles[i].position.x += sparkles[i].velocity.x * dt
            sparkles[i].position.y += sparkles[i].velocity.y * dt
            if sparkles[i].age >= sparkles[i].lifetime {
                sparkles.remove(at: i)
            }
        }

        // 10b. Overload smoke wisps — keep emitting while fried, then let them drift away.
        if isFried {
            smokeCooldown -= dt
            if smokeCooldown <= 0 {
                smokeCooldown = 0.14
                spawnSmoke(seatX: CatPhysics.seatAnchor.x + bodyShiftX.value)
            }
        }
        for i in smokePuffs.indices.reversed() {
            smokePuffs[i].age += dt
            smokePuffs[i].position.x += smokePuffs[i].velocity.x * dt
                + sin(smokePuffs[i].age * 2.6 + smokePuffs[i].seed) * 7 * dt
            smokePuffs[i].position.y += smokePuffs[i].velocity.y * dt
            if smokePuffs[i].age >= smokePuffs[i].lifetime {
                smokePuffs.remove(at: i)
            }
        }

        // 11. Music mode overlay (independent of typing — adds, never replaces)
        let music = MusicPulse.shared
        let musicOn = UserDefaults.standard.object(forKey: "KuroCat.MusicMode") as? Bool ?? false
        let active = musicOn && music.isPlaying && scripted == nil && !isFried  // fried face wins over music notes
        let presenceTarget: CGFloat = active ? 1.0 : 0.0
        equalizerPresence += (presenceTarget - equalizerPresence) * min(1, dt * 5.0)

        if active {
            // Head bob now clearly follows the real bass and beat impulses.
            let bobTarget = music.bass * 8.0 + music.beat * 11.0
            musicBounce += (bobTarget - musicBounce) * min(1, dt * 18)
            musicBounce *= (1 - dt * 2.2)

            // Beat-triggered happy squint, strong enough to actually read on screen
            if music.beat > 0.4 {
                musicBlinkBoost = 0.95
            }
            musicBlinkBoost = max(0, musicBlinkBoost - dt * 2.2)

            // Notes burst on beats and keep trickling while the track is loud
            if (music.beat > 0.4 && now - lastNoteTime > 0.16)
                || (music.level > 0.18 && now - lastNoteTime > 0.34) {
                spawnMusicNote(now: now)
                lastNoteTime = now
            }
        } else {
            musicBounce *= (1 - dt * 6)
            musicBlinkBoost = max(0, musicBlinkBoost - dt * 3)
        }

        // Update music note particles
        for i in musicNotes.indices.reversed() {
            musicNotes[i].age += dt
            musicNotes[i].position.x += musicNotes[i].velocity.x * dt
            musicNotes[i].position.y += musicNotes[i].velocity.y * dt
            musicNotes[i].velocity.y -= 7 * dt   // slight upward acceleration decay
            if musicNotes[i].age >= musicNotes[i].lifetime {
                musicNotes.remove(at: i)
            }
        }
    }

    // MARK: - Overload / fried helpers

    /// Test/preview hook: force the music-pulse visual overlay for headless snapshots.
    func previewSetMusic(presence: CGFloat, bounce: CGFloat, blink: CGFloat, noteCount: Int) {
        equalizerPresence = presence
        musicBounce = bounce
        musicBlinkBoost = blink
        musicNotes.removeAll()
        for i in 0..<noteCount {
            let glyphs = 4
            let n = MusicNoteParticle(
                position: CGPoint(
                    x: CatPhysics.seatAnchor.x + bodyShiftX.value + CGFloat.random(in: -58...58),
                    y: 96 - CGFloat(i) * 9 + CGFloat.random(in: -8...8)
                ),
                velocity: .zero,
                lifetime: 1.6,
                glyph: i % glyphs,
                rotation: CGFloat.random(in: -0.25...0.25),
                scale: CGFloat.random(in: 1.0...1.5)
            )
            musicNotes.append(n)
        }
        // stagger ages so notes appear at different heights
        for i in musicNotes.indices { musicNotes[i].age = 0.3 + CGFloat(i) * 0.14 }
    }

    /// Test/preview hook: force the overload state for headless visual verification.
    func previewSetOverload(strain s: CGFloat, fried: Bool, timeLeft: CGFloat = 3.0) {
        strain = s
        isFried = fried
        friedTimeLeft = timeLeft
        if fried {
            smokePuffs.removeAll()
            smokeCooldown = 0
            let seatX = CatPhysics.seatAnchor.x + bodyShiftX.value
            for _ in 0..<10 { spawnSmoke(seatX: seatX) }
        }
    }

    private func startFried(now: CFTimeInterval) {
        isFried = true
        friedTimeLeft = 3.0
        friedStartedAt = now
        strain = 0
        smokeCooldown = 0
        keyTimes.removeAll()
        fastStreakStart = 0
        lastFastKeyTime = 0
        overloadArmed = false

        // A strong first puff so the effect reads immediately.
        let seatX = CatPhysics.seatAnchor.x + bodyShiftX.value
        for _ in 0..<3 {
            spawnSmoke(seatX: seatX, strong: true)
        }

        // Snapshot: the fried face overrides notes and other expressions.
        musicNotes.removeAll()
    }

    private func endFried(now: CFTimeInterval) {
        isFried = false
        friedTimeLeft = 0
        // Refractory window so a continuing keystroke burst cannot instantly re-trigger.
        lastFastKeyTime = 0
        overloadArmed = false
        keyTimes.removeAll()
        fastStreakStart = 0
        strain = 0
        smokeCooldown = 0
    }

    private func spawnSmoke(seatX: CGFloat, strong: Bool = false) {
        let spread: CGFloat = strong ? 20 : 16
        let puff = SmokePuff(
            position: CGPoint(
                x: seatX + CGFloat.random(in: -spread...spread),
                y: 92 + CGFloat.random(in: -8...6)
            ),
            velocity: CGPoint(
                x: CGFloat.random(in: -7...7),
                y: -(strong ? CGFloat.random(in: 30...46) : CGFloat.random(in: 22...38))
            ),
            // Start slightly aged so the very first frame already shows a faint wisp
            // instead of being fully transparent (sin(0)=0).
            age: CGFloat.random(in: 0.18...0.5),
            lifetime: CGFloat.random(in: 1.0...1.7),
            radius: CGFloat.random(in: 6...11),
            seed: CGFloat.random(in: 0...6.28)
        )
        smokePuffs.append(puff)
        if smokePuffs.count > 26 { smokePuffs.removeFirst(smokePuffs.count - 26) }
    }

    private func spawnMusicNote(now: CFTimeInterval) {
        let headX = CatPhysics.seatAnchor.x + bodyShiftX.value
        let glyphs = 4
        noteGlyphIndex = (noteGlyphIndex + 1) % glyphs
        let music = MusicPulse.shared
        let note = MusicNoteParticle(
            position: CGPoint(
                x: headX + CGFloat.random(in: -54...54),
                y: 102 + CGFloat.random(in: -12...12)
            ),
            velocity: CGPoint(x: CGFloat.random(in: -16...16), y: -44 - music.level * 26 - CGFloat.random(in: 0...18)),
            lifetime: CGFloat.random(in: 1.2...1.8),
            glyph: noteGlyphIndex,
            rotation: CGFloat.random(in: -0.28...0.28),
            scale: CGFloat.random(in: 1.0...1.5) * (1.0 + music.beat * 0.25)
        )
        musicNotes.append(note)
        if musicNotes.count > 20 { musicNotes.removeFirst(musicNotes.count - 20) }
    }
}

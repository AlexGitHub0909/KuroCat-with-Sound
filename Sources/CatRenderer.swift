import Foundation
import CoreGraphics
import AppKit

enum CatHitZone {
    case none
    case head
    case body
    case permissionPill
}

enum CatRenderer {
    static let catBlack = NSColor(calibratedRed: 0.085, green: 0.085, blue: 0.095, alpha: 1.0)
    static let contourMint = NSColor(calibratedRed: 0.82, green: 0.92, blue: 0.89, alpha: 0.76)
    static let whiskerColor = NSColor(calibratedRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.72)

    // Siamese Seal-Point Palette (挖煤小暹罗: 暖燕麦奶白躯干 + 浓郁可可焦糖重点色)
    static let siameseCream   = NSColor(calibratedRed: 0.945, green: 0.905, blue: 0.835, alpha: 1.0) // #F1E7D5
    static let siameseLatte   = NSColor(calibratedRed: 0.865, green: 0.795, blue: 0.695, alpha: 1.0) // #DDCBB1
    static let siameseMocha   = NSColor(calibratedRed: 0.45,  green: 0.34,  blue: 0.27,  alpha: 1.0) // #735745
    static let siamesePoint   = NSColor(calibratedRed: 0.175, green: 0.128, blue: 0.105, alpha: 1.0) // #2D211B
    static let siameseOutline = NSColor(calibratedRed: 0.26,  green: 0.19,  blue: 0.155, alpha: 0.88)
    static let siameseWhisker = NSColor(calibratedRed: 0.36,  green: 0.27,  blue: 0.22,  alpha: 0.68)

    // Sakura pink palette (soft pink body + deeper rose points)
    static let pinkCream   = NSColor(calibratedRed: 1.00, green: 0.89, blue: 0.94, alpha: 1.0) // #FFE3F0
    static let pinkLatte   = NSColor(calibratedRed: 0.99, green: 0.75, blue: 0.85, alpha: 1.0) // #FCBFD9
    static let pinkMocha   = NSColor(calibratedRed: 0.88, green: 0.50, blue: 0.68, alpha: 1.0) // #E080AD
    static let pinkPoint   = NSColor(calibratedRed: 0.76, green: 0.33, blue: 0.55, alpha: 1.0) // #C2548C
    static let pinkOutline = NSColor(calibratedRed: 0.66, green: 0.28, blue: 0.48, alpha: 0.88)
    static let pinkWhisker = NSColor(calibratedRed: 0.66, green: 0.35, blue: 0.52, alpha: 0.68)

    static func isPointedCoat(_ coat: CatCoatTheme) -> Bool { coat != .classicBlack }
    static func coatCream(_ coat: CatCoatTheme) -> NSColor { coat == .pink ? pinkCream : siameseCream }
    static func coatLatte(_ coat: CatCoatTheme) -> NSColor { coat == .pink ? pinkLatte : siameseLatte }
    static func coatMocha(_ coat: CatCoatTheme) -> NSColor { coat == .pink ? pinkMocha : siameseMocha }
    static func coatPoint(_ coat: CatCoatTheme) -> NSColor { coat == .pink ? pinkPoint : siamesePoint }
    static func coatOutline(_ coat: CatCoatTheme) -> NSColor { coat == .pink ? pinkOutline : siameseOutline }
    static func coatWhisker(_ coat: CatCoatTheme) -> NSColor { coat == .pink ? pinkWhisker : siameseWhisker }

    static let permissionPillRect = CGRect(x: 92, y: 294, width: 176, height: 22)

    /// Hit test in 360x320 logical canvas coordinates for smart click-through & petting.
    static func hitTest(point p: CGPoint, physics: CatPhysics, showPermissionPill: Bool) -> CatHitZone {
        if showPermissionPill && permissionPillRect.insetBy(dx: -4, dy: -4).contains(p) {
            return .permissionPill
        }

        let cx = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let breath = sin(physics.time * 2.1) * 1.6
        let headCenter = CGPoint(x: cx + physics.bodyTilt.value * 42, y: 124 + physics.headOffsetY.value + breath)

        // Head hit ellipse (generous for cozy petting)
        let hdx = (p.x - headCenter.x) / 48.0
        let hdy = (p.y - headCenter.y) / 42.0
        if hdx * hdx + hdy * hdy <= 1.0 {
            return .head
        }

        // Torso + keyboard area hit check
        let bdx = (p.x - cx) / 58.0
        let bdy = (p.y - 196.0) / 56.0
        if bdx * bdx + bdy * bdy <= 1.0 {
            return .body
        }

        // Mini keyboard & mouse area (allows dragging by grabbing keyboard too)
        let kbRect = CGRect(x: 58, y: 232, width: 236, height: 64)
        if kbRect.contains(p) {
            return .body
        }

        return .none
    }

    /// Main 60fps draw routine in flipped 360x320 logical coordinate space.
    static func draw(in ctx: CGContext, physics: CatPhysics, showPermissionPill: Bool) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let settings = CatSettings.shared
        let coat = settings.coatTheme
        let breath = sin(physics.time * 2.1) * 1.6
        let seatX = CatPhysics.seatAnchor.x + physics.bodyShiftX.value
        let seatY = CatPhysics.seatAnchor.y

        // 1. Mini White Mouse (left of keyboard)
        drawMouse(in: ctx, physics: physics, theme: settings.keyboardTheme)

        // 2. Mini Angled 65% Mechanical Keyboard + Dynamic Keycap Glow
        drawKeyboard(in: ctx, physics: physics, theme: settings.keyboardTheme, eyeTheme: settings.eyeTheme)

        // 2.6 Music pickup / spectrum bars — a self-contained prop to the cat's right.
        // Painted behind the tail and body so it never overlaps the character.
        if physics.equalizerPresence > 0.01 {
            drawMusicEqualizer(in: ctx, physics: physics, eyeTheme: settings.eyeTheme)
        }

        // 3. Cat Tail (behind body)
        drawTail(in: ctx, seatX: seatX, seatY: seatY, physics: physics, coat: coat)

        // 4. 3D-Projected Ears (behind crown silhouette so Siamese seal-point ears emerge cleanly from cream skull!)
        let headCenter = CGPoint(
            x: seatX + physics.bodyTilt.value * 36 + physics.headYaw.value * 7.5,
            y: 126 + physics.headOffsetY.value + physics.headPitch.value * 4.8 + breath * 1.1
                - physics.musicBounce   // bob is part of the head itself, so ears and eyes stay locked together
        )
        drawEarsLayer(in: ctx, center: headCenter, physics: physics, coat: coat)

        // 5. Unified C1-Continuous Head + Neck + Pear Torso Silhouette + Siamese 2.5D Face Mask
        drawUnifiedSilhouette(
            in: ctx,
            seatX: seatX,
            seatY: seatY,
            headCenter: headCenter,
            breath: breath,
            physics: physics,
            coat: coat
        )

        // 6. Hind Foot (3rd simultaneous key easter egg!)
        if physics.hindFootActive.value > 0.03 {
            drawHindFoot(in: ctx, seatX: seatX, seatY: seatY, physics: physics, coat: coat)
        }

        // 7. 2.5D Turning Head Features: Luminous Eyes & Whiskers
        drawHeadFeatures(in: ctx, center: headCenter, physics: physics, eyeTheme: settings.eyeTheme, coat: coat)

        // 8. Front Arms / Paws (over torso & keyboard/mouse with crisp separation outlines / Siamese chocolate socks!)
        drawFrontPaws(in: ctx, seatX: seatX, seatY: seatY, breath: breath, physics: physics, coat: coat)

        // 8. Floating Mechanical Keycap Badges
        if settings.showKeyBadges {
            drawFloatingKeycaps(in: ctx, physics: physics)
        }

        // 8.5 Floating music notes (reuse the keycap/sparkle particle aesthetic) — hidden while fried
        if !physics.musicNotes.isEmpty && !physics.isFried {
            drawMusicNotes(in: ctx, physics: physics, eyeTheme: settings.eyeTheme)
        }

        // 9. Subtle Petting Sparkles / Sleep Z
        drawSparkles(in: ctx, physics: physics, eyeTheme: settings.eyeTheme)

        // 9b. Fried smoke wisps (drawn last so they hover clearly above the head)
        drawSmoke(in: ctx, physics: physics)

        // 10. Optional non-intrusive Permission Pill if global monitoring not yet granted
        if showPermissionPill {
            drawPermissionPill(in: ctx)
        }

        ctx.restoreGState()
    }

    // MARK: - Mini White Mouse

    private static func drawMouse(in ctx: CGContext, physics: CatPhysics, theme: KeyboardTheme) {
        let center = CGPoint(
            x: CatPhysics.mouseBaseCenter.x + physics.mouseOffset.point.x,
            y: CatPhysics.mouseBaseCenter.y + physics.mouseOffset.point.y
        )
        let pressShift = max(physics.mousePressLeft.value, physics.mousePressRight.value) * 1.6

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y + pressShift)
        ctx.rotate(by: 0.22) // angled naturally for the cat's right paw (facing the cat!)

        // Soft underside shadow
        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedWhite: 0.0, alpha: 0.24).cgColor)
        ctx.fillEllipse(in: CGRect(x: -13.5, y: -13.5 + 4.0, width: 27, height: 31))
        ctx.restoreGState()

        let bodyRect = CGRect(x: -13.5, y: -16.5, width: 27, height: 33)
        let bodyColor: NSColor
        let borderColor: NSColor
        let wheelColor: NSColor
        switch theme {
        case .classicMilk:
            bodyColor = NSColor(calibratedRed: 0.955, green: 0.950, blue: 0.925, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            bodyColor = NSColor(calibratedRed: 0.20, green: 0.21, blue: 0.24, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.10, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.78, green: 0.95, blue: 0.25, alpha: 1.0)
        case .retroCream:
            bodyColor = NSColor(calibratedRed: 0.89, green: 0.87, blue: 0.82, alpha: 1.0)
            borderColor = NSColor(calibratedRed: 0.20, green: 0.19, blue: 0.18, alpha: 1.0)
            wheelColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        // Mouse body (palm-rest dome toward cat at top, click buttons & scroll wheel away from cat at bottom!)
        ctx.setFillColor(bodyColor.cgColor)
        ctx.fillEllipse(in: bodyRect)

        // Subtle click flash highlight (cat-facing: left button = inner right side, right button = outer left side!)
        if physics.mousePressLeft.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressLeft.value).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }
        if physics.mousePressRight.value > 0.05 {
            ctx.saveGState()
            ctx.addEllipse(in: bodyRect)
            ctx.clip()
            ctx.setFillColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.38 * physics.mousePressRight.value).cgColor)
            ctx.fill(CGRect(x: -14, y: 0, width: 14, height: 17))
            ctx.restoreGState()
        }

        // Button split seam pointing forward (bottom, away from cat!)
        ctx.setStrokeColor(borderColor.withAlphaComponent(0.32).cgColor)
        ctx.setLineWidth(1.05)
        ctx.move(to: CGPoint(x: 0, y: 16))
        ctx.addLine(to: CGPoint(x: 0, y: 1.5))
        ctx.strokePath()

        // Signature amber scroll wheel on the front (bottom) half facing away from cat
        let wheelRect = CGRect(x: -1.9, y: 2.5, width: 3.8, height: 8.5)
        let wheelPath = CGPath(roundedRect: wheelRect, cornerWidth: 1.9, cornerHeight: 1.9, transform: nil)
        ctx.setFillColor(wheelColor.cgColor)
        ctx.addPath(wheelPath)
        ctx.fillPath()

        // Outer crisp outline
        ctx.setStrokeColor(borderColor.cgColor)
        ctx.setLineWidth(1.7)
        ctx.strokeEllipse(in: bodyRect)

        ctx.restoreGState()
    }

    // MARK: - Mini Angled 65% Mechanical Keyboard (facing the cat!)

    private static func drawKeyboard(
        in ctx: CGContext,
        physics: CatPhysics,
        theme: KeyboardTheme,
        eyeTheme: EyeColorTheme
    ) {
        let tl = KeyboardLayout.screenQuadPoint(su: -0.025, sv: -0.08)
        let tr = KeyboardLayout.screenQuadPoint(su: 1.025, sv: -0.08)
        let bl = KeyboardLayout.screenQuadPoint(su: -0.032, sv: 1.08)
        let br = KeyboardLayout.screenQuadPoint(su: 1.032, sv: 1.08)

        let caseDepth: CGFloat = 6.5

        // Soft ambient drop shadow beneath keyboard
        ctx.saveGState()
        let shadowPath = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth + 2),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth + 2),
            br: CGPoint(x: br.x, y: br.y + caseDepth + 3),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth + 3),
            radius: 6
        )
        ctx.setFillColor(NSColor(calibratedWhite: 0, alpha: 0.22).cgColor)
        ctx.addPath(shadowPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Dark 3D chassis lower lip
        let baseColor: NSColor
        let deckColor: NSColor
        let keyColor: NSColor
        let keyBorderColor: NSColor
        let accentColor: NSColor

        switch theme {
        case .classicMilk:
            baseColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.12, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.14, green: 0.14, blue: 0.16, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.968, green: 0.964, blue: 0.942, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.78, green: 0.77, blue: 0.74, alpha: 0.75)
            accentColor = NSColor(calibratedRed: 0.97, green: 0.70, blue: 0.16, alpha: 1.0)
        case .midnightHacker:
            baseColor = NSColor(calibratedRed: 0.06, green: 0.06, blue: 0.08, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.21, green: 0.22, blue: 0.25, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.95)
            accentColor = NSColor(calibratedRed: 0.77, green: 0.94, blue: 0.25, alpha: 1.0)
        case .retroCream:
            baseColor = NSColor(calibratedRed: 0.25, green: 0.24, blue: 0.22, alpha: 1.0)
            deckColor = NSColor(calibratedRed: 0.38, green: 0.36, blue: 0.33, alpha: 1.0)
            keyColor = NSColor(calibratedRed: 0.90, green: 0.88, blue: 0.82, alpha: 1.0)
            keyBorderColor = NSColor(calibratedRed: 0.68, green: 0.65, blue: 0.60, alpha: 0.85)
            accentColor = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
        }

        let lowerChassis = roundedQuadPath(
            tl: CGPoint(x: tl.x, y: tl.y + caseDepth),
            tr: CGPoint(x: tr.x, y: tr.y + caseDepth),
            br: CGPoint(x: br.x, y: br.y + caseDepth),
            bl: CGPoint(x: bl.x, y: bl.y + caseDepth),
            radius: 5.5
        )
        ctx.setFillColor(baseColor.cgColor)
        ctx.addPath(lowerChassis)
        ctx.fillPath()

        let topChassis = roundedQuadPath(tl: tl, tr: tr, br: br, bl: bl, radius: 5.0)
        ctx.setFillColor(deckColor.cgColor)
        ctx.addPath(topChassis)
        ctx.fillPath()

        // Individual keycaps — tight clean mechanical spacing matching the reference video
        let padU: CGFloat = 0.0028
        let padV: CGFloat = 0.014
        let glowBaseColor = eyeTheme.glowColor

        for cap in KeyboardLayout.keycaps {
            let glow = physics.keyGlow[cap.key] ?? 0
            // 180° rotated to face the cat: su = 1 - u, sv = 1 - v
            let su0 = (1.0 - (cap.xUnits + cap.widthUnits)) + padU
            let su1 = (1.0 - cap.xUnits) - padU
            let sv0 = (1.0 - CGFloat(cap.row + 1) / 5.0) + padV
            let sv1 = (1.0 - CGFloat(cap.row) / 5.0) - padV

            let pressDy = glow * 1.9
            let kTL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv0), pressDy)
            let kTR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv0), pressDy)
            let kBR = offsetY(KeyboardLayout.screenQuadPoint(su: su1, sv: sv1), pressDy)
            let kBL = offsetY(KeyboardLayout.screenQuadPoint(su: su0, sv: sv1), pressDy)

            let kPath = roundedQuadPath(tl: kTL, tr: kTR, br: kBR, bl: kBL, radius: 1.6)

            var fill = cap.isAmberAccent ? accentColor : keyColor
            if glow > 0.02 {
                fill = blendColor(fill, glowBaseColor, t: glow * 0.55)
            }

            ctx.setFillColor(fill.cgColor)
            ctx.addPath(kPath)
            ctx.fillPath()

            ctx.setStrokeColor(keyBorderColor.cgColor)
            ctx.setLineWidth(0.65)
            ctx.addPath(kPath)
            ctx.strokePath()
        }

        // Signature soft chartreuse backlit glow halos on active keys!
        for (key, glow) in physics.keyGlow where glow > 0.05 {
            let center = KeyboardLayout.canvasPoint(for: key)
            drawRadialGlow(
                in: ctx,
                center: center,
                radius: 17.0 + glow * 6.0,
                color: glowBaseColor.withAlphaComponent(0.36 * glow)
            )
        }
    }

    // MARK: - Tail

    private static func drawTail(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat, physics: CatPhysics, coat: CatCoatTheme) {
        let p = physics.tailPhase
        let hunt = max(0, min(1, physics.huntIntensity.value))
        let wag1 = sin(p) * (8.0 + hunt * 5.5)
        let wag2 = cos(p * 1.3) * (6.0 + hunt * 4.5)
        // Tail drops lower & swishes tautly when stalking/hunting!
        let huntDrop = hunt * 14.0

        // Signature low sweep out to the right, then playful upward curl at the tip!
        let root = CGPoint(x: seatX + 34, y: seatY - 6)
        let c1 = CGPoint(x: seatX + 64, y: seatY + 2 + wag1 * 0.35 + huntDrop * 0.4)
        let c2 = CGPoint(x: seatX + 66 + wag2 * 0.4, y: seatY - 26 + wag1 * 0.7 + huntDrop)
        let tip = CGPoint(x: seatX + 91 + wag2 * 0.5, y: seatY - 30 + wag1 * 0.85 + huntDrop)

        ctx.saveGState()
        let tailColor = isPointedCoat(coat) ? coatPoint(coat) : catBlack
        ctx.setStrokeColor(tailColor.cgColor)
        ctx.setLineWidth(11.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: root)
        ctx.addCurve(to: tip, control1: c1, control2: c2)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Unified C1-Continuous Cat Silhouette (Crown -> Cheeks -> Plush Neck -> Pear Hips)

    private static func drawUnifiedSilhouette(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        headCenter: CGPoint,
        breath: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let yaw = physics.headYaw.value
        let pitch = physics.headPitch.value
        let hTilt = physics.headTilt.value
        let bTilt = physics.bodyTilt.value

        let cH = cos(hTilt), sH = sin(hTilt)
        func H(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            CGPoint(
                x: headCenter.x + lx * cH - ly * sH,
                y: headCenter.y + lx * sH + ly * cH
            )
        }

        let cB = cos(bTilt), sB = sin(bTilt)
        let sy = physics.bodySquash.value
        let sx = 1.0 + (1.0 - sy) * 0.55
        func B(_ lx: CGFloat, _ ly: CGFloat) -> CGPoint {
            let rx = lx * sx
            let ry = ly * sy
            return CGPoint(
                x: seatX + rx * cB - ry * sB,
                y: seatY + rx * sB + ry * cB
            )
        }

        let cheekShift = yaw * 3.0
        let crownDrop = pitch * 2.0
        let leftCheekX: CGFloat = -42.5 + cheekShift * 0.4
        let rightCheekX: CGFloat = 42.5 + cheekShift * 0.4

        // ONE single tangent-continuous closed cubic Bezier path — mathematically impossible to form any ledge or protrusion!
        let crown  = H(cheekShift * 0.2, -30 + crownDrop)
        let rCheek = H(rightCheekX, 5)
        let rHip   = B(49.0, -14)
        let rBot   = B(24.0, 12)
        let lBot   = B(-24.0, 12)
        let lHip   = B(-49.0, -14)
        let lCheek = H(leftCheekX, 5)

        let path = CGMutablePath()
        path.move(to: crown)
        path.addCurve(to: rCheek, control1: H(26 + cheekShift * 0.3, -30 + crownDrop), control2: H(rightCheekX + 1.5, -14))
        path.addCurve(to: rHip,   control1: H(rightCheekX - 2.5, 24), control2: B(51.5, -48 + breath * 0.5))
        path.addCurve(to: rBot,   control1: B(47.0, 5), control2: B(36.0, 12))
        path.addLine(to: lBot)
        path.addCurve(to: lHip,   control1: B(-36.0, 12), control2: B(-47.0, 5))
        path.addCurve(to: lCheek, control1: B(-51.5, -48 + breath * 0.5), control2: H(leftCheekX + 2.5, 24))
        path.addCurve(to: crown,  control1: H(leftCheekX - 1.5, -14), control2: H(-26 + cheekShift * 0.3, -30 + crownDrop))
        path.closeSubpath()

        ctx.saveGState()
        if coat == .classicBlack {
            ctx.setFillColor(catBlack.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        } else {
            // Siamese warm oat-milk cream gradient + soft toasted back shading + 2.5D rotating seal-point face mask!
            ctx.addPath(path)
            ctx.clip()

            let cs = CGColorSpaceCreateDeviceRGB()
            let bodyColors = [coatCream(coat).cgColor, coatLatte(coat).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: bodyColors, locations: [0.15, 1.0]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: seatX, y: headCenter.y - 34),
                    end: CGPoint(x: seatX, y: seatY + 18),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // Soft toasted ear-base blend at top crown so espresso ears melt organically into cream head
            let yawRad = yaw * 0.50
            let pitchRad = pitch * 0.36
            ctx.saveGState()
            ctx.translateBy(x: headCenter.x, y: headCenter.y)
            ctx.rotate(by: hTilt)

            // 2.5D Rotating Seal-Point "挖煤" Face Mask (moves naturally across cheeks as head turns!)
            let maskCenter = projectHead3D(x: 0, y: 2.5, z: 27.0, yawRad: yawRad, pitchRad: pitchRad).pt
            let maskScaleX = max(0.76, cos(yawRad * 0.7))
            let maskScaleY = max(0.82, cos(pitchRad * 0.7))
            ctx.saveGState()
            ctx.translateBy(x: maskCenter.x, y: maskCenter.y)
            ctx.scaleBy(x: maskScaleX * 1.18, y: maskScaleY * 0.88)
            let maskColors = [
                coatPoint(coat).cgColor,
                coatPoint(coat).withAlphaComponent(0.96).cgColor,
                coatMocha(coat).withAlphaComponent(0.70).cgColor,
                coatMocha(coat).withAlphaComponent(0.0).cgColor
            ] as CFArray
            if let maskGrad = CGGradient(colorsSpace: cs, colors: maskColors, locations: [0.0, 0.44, 0.74, 1.0]) {
                ctx.drawRadialGradient(
                    maskGrad,
                    startCenter: .zero, startRadius: 2,
                    endCenter: .zero, endRadius: 31,
                    options: []
                )
            }
            ctx.restoreGState()
            ctx.restoreGState()
        }
        ctx.restoreGState()

        // Crisp subtle warm-cocoa outline around Siamese cream body so it pops on light & dark wallpapers!
        if isPointedCoat(coat) {
            ctx.saveGState()
            ctx.setStrokeColor(coatOutline(coat).cgColor)
            ctx.setLineWidth(1.5)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }

        // Tucked hind paws peeking softly along bottom edge
        ctx.saveGState()
        ctx.translateBy(x: seatX, y: seatY)
        ctx.rotate(by: bTilt)
        ctx.scaleBy(x: sx, y: sy)
        ctx.setFillColor((isPointedCoat(coat) ? coatPoint(coat) : catBlack).cgColor)

        ctx.fillEllipse(in: CGRect(x: -35, y: 3, width: 17, height: 11))
        if physics.hindFootActive.value < 0.35 {
            ctx.fillEllipse(in: CGRect(x: 18, y: 3, width: 17, height: 11))
        }

        // Subtle bottom rim highlights on tucked haunches
        let rimColor = isPointedCoat(coat) ? coatCream(coat).withAlphaComponent(0.55) : contourMint.withAlphaComponent(0.58)
        ctx.setStrokeColor(rimColor.cgColor)
        ctx.setLineWidth(1.3)
        ctx.setLineCap(.round)
        ctx.addArc(center: CGPoint(x: -26.5, y: 8.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
        ctx.strokePath()
        if physics.hindFootActive.value < 0.35 {
            ctx.addArc(center: CGPoint(x: 26.5, y: 8.5), radius: 7.5, startAngle: 0.25, endAngle: .pi - 0.25, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - 3rd Key Hind Foot Easter Egg

    private static func drawHindFoot(in ctx: CGContext, seatX: CGFloat, seatY: CGFloat, physics: CatPhysics, coat: CatCoatTheme) {
        let hip = CGPoint(x: seatX + 26, y: seatY + 2)
        let target = physics.hindFoot.point
        let mid = CGPoint(
            x: (hip.x + target.x) * 0.5 + 10,
            y: (hip.y + target.y) * 0.5 - 8
        )

        drawLimb(
            in: ctx,
            start: hip,
            control: mid,
            end: target,
            startWidth: 15.0,
            endWidth: 12.0,
            outlineOnLeftSide: true,
            outlineAlpha: 0.85 * physics.hindFootActive.value,
            coat: coat
        )
    }

    // MARK: - 2.5D Spherical Head Projection Helper

    /// Projects a 3D point on the cat's head ellipsoid rotated by (yawRad, pitchRad)
    /// into 2D head-local coordinates — creating true Live2D-style 2.5D head turning!
    private static func projectHead3D(
        x: CGFloat, y: CGFloat, z: CGFloat,
        yawRad: CGFloat, pitchRad: CGFloat
    ) -> (pt: CGPoint, z: CGFloat) {
        // 1. Yaw around Y axis (positive yaw = turning right toward viewer's right)
        let cy = cos(yawRad)
        let sy = sin(yawRad)
        let x1 = x * cy + z * sy
        let z1 = -x * sy + z * cy

        // 2. Pitch around X axis (positive pitch = nodding down)
        let cp = cos(pitchRad)
        let sp = sin(pitchRad)
        let y2 = y * cp + z1 * sp
        let z2 = -y * sp + z1 * cp

        return (CGPoint(x: x1, y: y2), z2)
    }

    // MARK: - 2.5D Ears Layer (drawn behind unified silhouette so Siamese seal-point ears emerge organically!)

    private static func drawEarsLayer(
        in ctx: CGContext,
        center: CGPoint,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yawRad = physics.headYaw.value * 0.50
        let pitchRad = physics.headPitch.value * 0.36
        let fold = physics.earFold.value
        let twitch = physics.earTwitch.value * 0.045

        drawEar3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: twitch, coat: coat)
        drawEar3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, fold: fold, twitch: -twitch, coat: coat)

        ctx.restoreGState()
    }

    // MARK: - Music Pickup / Spectrum Bars

    /// Six little glowing note-capsules to the right of the cat. Driven by the real
    /// 6-band spectrum, but styled like the project's soft rounded particles rather
    /// than a hard audio meter — no rail, no tracks, just floating light.
    private static func drawMusicEqualizer(in ctx: CGContext, physics: CatPhysics, eyeTheme: EyeColorTheme) {
        let music = MusicPulse.shared
        let fade = min(1.0, max(0.0, physics.equalizerPresence))
        let bands = music.bands
        let barW: CGFloat = 9
        let gap: CGFloat = 5
        let originX: CGFloat = 250
        let baseY: CGFloat = 188
        let maxH: CGFloat = 100
        let accent = eyeTheme.primaryColor
        let space = CGColorSpaceCreateDeviceRGB()

        ctx.saveGState()
        ctx.setAlpha(fade)

        for i in 0..<bands.count {
            let x = originX + CGFloat(i) * (barW + gap)
            // Real spectrum with a gentle curve so quiet bands stay legible, plus a
            // shared beat lift so the whole group visibly pulses on the downbeat.
            let raw = min(1.0, max(0.0, bands[i]))
            let value = min(1.0, pow(raw, 0.52) + music.beat * 0.16)
            let h = max(13.0, value * maxH)

            // Soft halo behind each capsule
            let glowRect = CGRect(x: x - 2.5, y: baseY - h - 2.5, width: barW + 5, height: h + 5)
            ctx.setFillColor(accent.withAlphaComponent(0.10).cgColor)
            ctx.addPath(CGPath(roundedRect: glowRect, cornerWidth: (barW + 5) / 2,
                               cornerHeight: (barW + 5) / 2, transform: nil))
            ctx.fillPath()

            // Rounded capsule, brighter toward the tip
            let capsule = CGPath(roundedRect: CGRect(x: x, y: baseY - h, width: barW, height: h),
                                 cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil)
            let colors = [accent.withAlphaComponent(0.40).cgColor,
                          accent.withAlphaComponent(0.90).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
                ctx.saveGState()
                ctx.addPath(capsule)
                ctx.clip()
                ctx.drawLinearGradient(gradient,
                                       start: CGPoint(x: x, y: baseY),
                                       end: CGPoint(x: x, y: baseY - h),
                                       options: [])
                ctx.restoreGState()
            }

            // Falling peak cap floats above the capsule — the classic "bounce" cue.
            // Tinted from the theme color so it reads as part of the same glow.
            let peakRaw = min(1.0, max(0.0, music.bandPeaks[i]))
            let peakValue = min(1.0, pow(peakRaw, 0.52) + music.beat * 0.16)
            let peakY = baseY - max(peakValue * maxH, h + 3)
            let tint = accent.usingColorSpace(.deviceRGB) ?? accent
            ctx.setFillColor(NSColor(calibratedRed: tint.redComponent * 0.55,
                                     green: tint.greenComponent * 0.55,
                                     blue: tint.blueComponent * 0.55,
                                     alpha: 0.75).cgColor)
            ctx.fill(CGRect(x: x + 1, y: peakY, width: barW - 2, height: 2.0))

            // A tiny light hovering just above the tip — like a floating note head
            let beadR: CGFloat = 1.8 + value * 1.2 + music.beat * 0.9
            let beadCY = peakY - beadR - 1.0
            ctx.setFillColor(accent.withAlphaComponent(0.95).cgColor)
            ctx.fillEllipse(in: CGRect(x: x + barW / 2 - beadR,
                                       y: beadCY - beadR,
                                       width: beadR * 2, height: beadR * 2))
        }

        ctx.restoreGState()
    }

    // MARK: - Floating Music Notes (music-mode particle layer)

    private static func drawMusicNotes(in ctx: CGContext, physics: CatPhysics, eyeTheme: EyeColorTheme) {
        let glyphs = ["♪", "♫", "♩", "♬"]
        for note in physics.musicNotes {
            let progress = note.age / note.lifetime
            let alpha = sin(min(1.0, progress) * .pi) * 0.92
            let popScale: CGFloat = progress < 0.12 ? (0.7 + 0.3 * (progress / 0.12)) : 1.0

            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: note.position.x, y: note.position.y)
            ctx.rotate(by: note.rotation + sin(progress * .pi * 2) * 0.12)
            ctx.scaleBy(x: note.scale * popScale, y: note.scale * popScale)

            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 20, weight: .medium),
                .foregroundColor: eyeTheme.primaryColor
            ]
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            let str = NSAttributedString(string: glyphs[note.glyph % glyphs.count], attributes: attrs)
            str.draw(at: CGPoint(x: -str.size().width/2, y: -str.size().height/2))
            NSGraphicsContext.restoreGraphicsState()

            ctx.restoreGState()
        }
    }

    // MARK: - 2.5D Head Features (Luminous Eyes & Whiskers)

    private static func drawHeadFeatures(
        in ctx: CGContext,
        center: CGPoint,
        physics: CatPhysics,
        eyeTheme: EyeColorTheme,
        coat: CatCoatTheme
    ) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: physics.headTilt.value)

        let yaw = physics.headYaw.value      // -1 (left) .. +1 (right)
        let pitch = physics.headPitch.value  // -1 (up)   .. +1 (down)
        let yawRad = yaw * 0.50              // ~±28.5° authentic head turn
        let pitchRad = pitch * 0.36          // ~±20.5° authentic head nod

        // 1. 3D-Projected Eyes with authentic spherical foreshortening & parallax!
        drawEye3D(in: ctx, isLeft: true, yawRad: yawRad, pitchRad: pitchRad, physics: physics, eyeTheme: eyeTheme, coat: coat)
        drawEye3D(in: ctx, isLeft: false, yawRad: yawRad, pitchRad: pitchRad, physics: physics, eyeTheme: eyeTheme, coat: coat)

        // 1b. Overload mouth: gritted teeth when straining, flat dazed line when fried.
        if physics.isFried || physics.isStraining {
            drawOverloadMouth(in: ctx, yawRad: yawRad, pitchRad: pitchRad, physics: physics, coat: coat)
        }

        // 1c. Tier-3 extras: comic anger vein + sweat drop for the "ALL OUT" look.
        if physics.isStraining && physics.strainTier >= 3 {
            drawStrainExtras(in: ctx, yawRad: yawRad, pitchRad: pitchRad, physics: physics, eyeTheme: eyeTheme)
        }

        // 2. 3D-Projected Whiskers (outer-side whiskers poke out past silhouette when turning!)
        drawWhiskers3D(in: ctx, yawRad: yawRad, pitchRad: pitchRad, physics: physics, coat: coat)

        ctx.restoreGState()
    }

    /// Small centered mouth between/below the eyes — gritted teeth or a flat dazed squiggle.
    private static func drawOverloadMouth(
        in ctx: CGContext,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let proj = projectHead3D(x: 0, y: 12.5, z: 29.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let ink: NSColor = isPointedCoat(coat) ? coatPoint(coat) : catBlack
        ctx.saveGState()
        ctx.translateBy(x: proj.x, y: proj.y)

        if physics.isFried {
            // Wobbly, flat "I'm done" mouth — themed so it stays visible on dark fur.
            ctx.setStrokeColor(NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.60, alpha: 0.85).cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -5.5, y: 0))
            ctx.addQuadCurve(to: CGPoint(x: -1.8, y: 1.6), control: CGPoint(x: -3.6, y: -0.8))
            ctx.addQuadCurve(to: CGPoint(x: 1.8, y: 0.2), control: CGPoint(x: 0, y: 2.6))
            ctx.addQuadCurve(to: CGPoint(x: 5.5, y: 1.4), control: CGPoint(x: 3.6, y: -1.0))
            ctx.strokePath()
        } else {
            // Straining mouth escalates: tier 1 = tight line, 2 = gritted teeth, 3 = bared fangs.
            let tier = physics.strainTier
            if tier <= 1 {
                // Tightly pressed line — holding it together.
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(1.8)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: -5.0, y: 0))
                ctx.addQuadCurve(to: CGPoint(x: 5.0, y: 0), control: CGPoint(x: 0, y: -1.0))
                ctx.strokePath()
            } else {
                let fangs = tier >= 3
                let halfW: CGFloat = fangs ? 8.0 : 6.5
                let barH: CGFloat = fangs ? 5.4 : 4.4
                ctx.setFillColor(ink.cgColor)
                ctx.fill(CGRect(x: -halfW, y: -2.0, width: halfW * 2, height: barH))
                ctx.setFillColor(NSColor(calibratedWhite: 0.95, alpha: 0.94).cgColor)
                let step: CGFloat = fangs ? 3.0 : 2.6
                var x: CGFloat = -halfW + 1.3
                while x < halfW - 1.3 {
                    if fangs {
                        // Pointed fangs for the all-out tier.
                        let f = CGMutablePath()
                        f.move(to: CGPoint(x: x - 0.9, y: -1.8))
                        f.addLine(to: CGPoint(x: x + 0.9, y: -1.8))
                        f.addLine(to: CGPoint(x: x, y: -1.8 - (step == 3.0 ? 2.6 : 1.9)))
                        f.closeSubpath()
                        ctx.addPath(f); ctx.fillPath()
                    } else {
                        ctx.fill(CGRect(x: x - 0.85, y: -1.8, width: 1.7, height: 1.9))
                    }
                    x += step
                }
                // Upper lip curl, more pronounced at tier 3.
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(fangs ? 1.6 : 1.2)
                ctx.move(to: CGPoint(x: -halfW - 0.5, y: 3.2))
                ctx.addQuadCurve(to: CGPoint(x: halfW + 0.5, y: 3.2),
                                 control: CGPoint(x: 0, y: fangs ? 0.8 : 1.6))
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }

    /// Tier-3 only: a comic popping-anger-vein (💢) over the brow and a flying sweat drop.
    private static func drawStrainExtras(
        in ctx: CGContext,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        eyeTheme: EyeColorTheme
    ) {
        let accent = eyeTheme.primaryColor
        let jitter = sin(physics.time * 34) * 0.8  // trembling with effort

        // Anger vein: four short strokes radiating from a center, drawn above the brow.
        let vein = projectHead3D(x: 22, y: -34, z: 20, yawRad: yawRad, pitchRad: pitchRad).pt
        ctx.saveGState()
        ctx.translateBy(x: vein.x, y: vein.y + jitter)
        ctx.rotate(by: -0.18 + sin(physics.time * 9) * 0.06)
        ctx.setStrokeColor(accent.cgColor)
        ctx.setLineWidth(2.2)
        ctx.setLineCap(.round)
        // small diamond core (build on a path — CGContext has no closeSubpath)
        let core = CGMutablePath()
        core.move(to: CGPoint(x: 0, y: -3.2))
        core.addLine(to: CGPoint(x: 3.2, y: 0))
        core.addLine(to: CGPoint(x: 0, y: 3.2))
        core.addLine(to: CGPoint(x: -3.2, y: 0))
        core.closeSubpath()
        ctx.addPath(core)
        ctx.strokePath()
        // radiating ticks
        let rays = CGMutablePath()
        let rayCoords: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-6.0, -6.0, -3.2, -3.2), (6.0, -6.0, 3.2, -3.2),
            (-6.0, 6.0, -3.2, 3.2), (6.0, 6.0, 3.2, 3.2),
            (0, -8.2, 0, -4.6)
        ]
        for r in rayCoords {
            rays.move(to: CGPoint(x: r.0, y: r.1))
            rays.addLine(to: CGPoint(x: r.2, y: r.3))
        }
        ctx.addPath(rays)
        ctx.strokePath()
        ctx.restoreGState()

        // Sweat drop flinging off the other side of the head — pale blue-teardrop.
        let sweat = projectHead3D(x: -34, y: -26, z: 16, yawRad: yawRad, pitchRad: pitchRad).pt
        let fly = sin(physics.time * 12) * 1.6
        ctx.saveGState()
        ctx.translateBy(x: sweat.x - 3 + fly, y: sweat.y - 2)
        ctx.rotate(by: -0.28)
        ctx.setFillColor(NSColor(calibratedRed: 0.62, green: 0.84, blue: 0.94, alpha: 0.92).cgColor)
        let drop = CGMutablePath()
        drop.move(to: CGPoint(x: 0, y: -5.5))
        drop.addQuadCurve(to: CGPoint(x: 4.0, y: 1.5), control: CGPoint(x: 3.6, y: -3.0))
        drop.addQuadCurve(to: CGPoint(x: 0, y: 5.5), control: CGPoint(x: 4.4, y: 5.2))
        drop.addQuadCurve(to: CGPoint(x: -4.0, y: 1.5), control: CGPoint(x: -4.4, y: 5.2))
        drop.addQuadCurve(to: CGPoint(x: 0, y: -5.5), control: CGPoint(x: -3.6, y: -3.0))
        drop.closeSubpath()
        ctx.addPath(drop)
        ctx.fillPath()
        // tiny highlight
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: -1.6, y: 0.4, width: 1.8, height: 2.4))
        ctx.restoreGState()
    }

    private static func drawEar3D(
        in ctx: CGContext,
        isLeft: Bool,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        fold: CGFloat,
        twitch: CGFloat,
        coat: CatCoatTheme
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let foldAngle = sign * (0.06 + fold * 0.34) + twitch

        let tipDx = sin(foldAngle) * 32.0
        let tipDy = -cos(foldAngle) * 32.0

        // Bases anchored comfortably inside the upper skull contour so they merge seamlessly at every yaw/pitch!
        let innerBase3D = projectHead3D(x: sign * 9.0, y: -16.0, z: 0.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let outerBase3D = projectHead3D(x: sign * 35.0, y: -5.0, z: -2.0, yawRad: yawRad, pitchRad: pitchRad).pt
        let tip3D       = projectHead3D(x: sign * 24.5 + tipDx, y: -20.0 + tipDy, z: -3.0, yawRad: yawRad, pitchRad: pitchRad).pt

        // Soft plush rounded-tip feline ear
        let tipLeft  = CGPoint(x: tip3D.x - sign * 3.8, y: tip3D.y + 2.8)
        let tipRight = CGPoint(x: tip3D.x + sign * 3.8, y: tip3D.y + 3.2)

        let ear = CGMutablePath()
        ear.move(to: innerBase3D)
        ear.addQuadCurve(
            to: tipLeft,
            control: CGPoint(x: (innerBase3D.x + tipLeft.x) * 0.5 - sign * 1.5, y: (innerBase3D.y + tipLeft.y) * 0.5 - 2.0)
        )
        ear.addQuadCurve(to: tipRight, control: CGPoint(x: tip3D.x, y: tip3D.y - 2.2))
        ear.addQuadCurve(
            to: outerBase3D,
            control: CGPoint(x: (outerBase3D.x + tipRight.x) * 0.5 + sign * 2.5, y: (outerBase3D.y + tipRight.y) * 0.5 - 2.0)
        )
        ear.closeSubpath()

        ctx.saveGState()
        ctx.setFillColor((isPointedCoat(coat) ? coatPoint(coat) : catBlack).cgColor)
        ctx.addPath(ear)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawEye3D(
        in ctx: CGContext,
        isLeft: Bool,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        eyeTheme: EyeColorTheme,
        coat: CatCoatTheme
    ) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        let eyeColor = eyeTheme.primaryColor

        // Eye sits on the front surface of the 3D head sphere at (±17.5, -2.0, +28.0)
        let proj = projectHead3D(x: sign * 17.2, y: -2.0, z: 27.5, yawRad: yawRad, pitchRad: pitchRad)

        // Authentic spherical foreshortening: the eye turning away toward the edge narrows horizontally!
        let eyeNormalAngle = yawRad + sign * 0.34
        let foreshortenX = max(0.64, min(1.06, cos(eyeNormalAngle) / cos(0.34)))
        let foreshortenY = max(0.78, min(1.03, cos(pitchRad * 0.85)))

        ctx.saveGState()
        ctx.translateBy(x: proj.pt.x, y: proj.pt.y)
        ctx.scaleBy(x: foreshortenX, y: foreshortenY)

        let faceInk: NSColor = isPointedCoat(coat) ? coatPoint(coat) : catBlack

        // Mode -1: FRIED / DAZED — half-lidded vacant eyes, pupils drifting out of sync.
        // Takes priority over every other expression while the 3s smoke effect runs.
        if physics.isFried {
            let eRect = CGRect(x: -11.6, y: -7.8, width: 23.2, height: 15.6)
            ctx.setFillColor(eyeColor.withAlphaComponent(0.5).cgColor)
            ctx.fillEllipse(in: eRect)

            // Small, dim, unfocused pupils sitting LOW so the drooping lid still reveals them.
            let drift = sin(physics.time * 1.7 + (isLeft ? 0 : 2.3)) * 1.8
            let px = (isLeft ? -2.8 : 2.6) + drift
            let py: CGFloat = 3.0 + cos(physics.time * 1.3 + (isLeft ? 0.5 : 2.0)) * 0.9
            ctx.setFillColor(faceInk.cgColor)
            ctx.fillEllipse(in: CGRect(x: px - 2.2, y: py - 2.4, width: 4.4, height: 4.8))

            // Heavy drooping upper lid covers the TOP portion only — pupils stay visible below.
            let lidPath = CGMutablePath()
            lidPath.move(to: CGPoint(x: -12.6, y: 7.8))
            lidPath.addLine(to: CGPoint(x: -12.6, y: 0.5))
            lidPath.addQuadCurve(to: CGPoint(x: 12.6, y: 0.5), control: CGPoint(x: 0, y: -2.2))
            lidPath.addLine(to: CGPoint(x: 12.6, y: 7.8))
            lidPath.closeSubpath()
            ctx.setFillColor(faceInk.cgColor)
            ctx.addPath(lidPath)
            ctx.fillPath()
            // Tired crease along the drooping lid edge, in theme color so it reads on black fur.
            ctx.setStrokeColor(eyeColor.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -10.8, y: 0.5))
            ctx.addQuadCurve(to: CGPoint(x: 10.8, y: 0.5), control: CGPoint(x: 0, y: -1.8))
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        // Mode 0: STRAINING — three escalating tiers of effort while typing too fast.
        // tier 1 = slight exertion, 2 = really trying, 3 = all-out.
        if physics.isStraining {
            let tier = physics.strainTier
            // 0..1 progress inside the whole straining band, used for smooth per-frame nuance.
            let s = min(1, max(0, (physics.strain - 0.42) / 0.58))
            // Tier weights (t1 / t2 / t3) drive how extreme each feature gets.
            let w1: CGFloat = tier == 1 ? 1 : (tier == 2 ? 0.55 : 0.3)
            let w2: CGFloat = tier == 2 ? 1 : (tier == 3 ? 0.6 : 0)
            let w3: CGFloat = tier == 3 ? 1 : 0

            // Eye height shrinks with effort: wide-ish -> squint -> razor sliver at tier 3.
            let halfH: CGFloat = tier == 3 ? 3.6 : (8.8 - 2.2 * w1 - 1.8 * w2)
            let eRect = CGRect(x: -12.2, y: -halfH, width: 24.4, height: halfH * 2)
            ctx.setFillColor(eyeColor.cgColor)
            ctx.fillEllipse(in: eRect)

            // Pupil narrows from oval -> tight slit as effort climbs.
            let gaze = physics.eyeGaze.point
            let px = gaze.x * (3.0 - 1.0 * w3)
            let pupilW: CGFloat = 4.6 - 1.6 * w2 - 0.9 * w3
            let pupilH: CGFloat = halfH * 1.7
            ctx.setFillColor(faceInk.cgColor)
            ctx.fillEllipse(in: CGRect(x: px - pupilW / 2, y: -pupilH / 2, width: pupilW, height: pupilH))

            // Upper lid presses down harder each tier (top squeeze).
            let topSqueeze: CGFloat = 2.4 + 1.8 * w1 + 1.6 * w2 + 1.4 * w3
            ctx.setFillColor(faceInk.cgColor)
            ctx.fill(CGRect(x: -12.6, y: -halfH - 0.8, width: 25.2, height: topSqueeze))

            // Furrowed brow: deeper, thicker and more steeply angled with each tier.
            // Tier 3 gets a heavy, near-horizontal scowl slammed low over the eyes.
            ctx.setStrokeColor(eyeColor.withAlphaComponent(0.72 + 0.1 * w3).cgColor)
            ctx.setLineWidth(tier == 3 ? 4.6 : (2.2 + 0.5 * w2))
            ctx.setLineCap(.round)
            let innerX: CGFloat = isLeft ? 9.5 : -9.5
            let outerX: CGFloat = isLeft ? -11.0 : 11.0
            let outerY: CGFloat = tier == 3 ? -9.4 : (-10.6 - 1.4 * w1 - 1.3 * w2)
            let innerY: CGFloat = tier == 3 ? -6.6 : (-7.8 - 2.2 * w1 - 2.3 * w2)
            ctx.move(to: CGPoint(x: outerX, y: outerY))
            ctx.addQuadCurve(to: CGPoint(x: innerX, y: innerY),
                             control: CGPoint(x: (outerX + innerX) * 0.5, y: outerY - 0.5))
            ctx.strokePath()

            // Tier 3: little strain ticks at the outer eye corner (effort / trembling).
            if tier >= 3 {
                ctx.setStrokeColor(eyeColor.withAlphaComponent(0.75).cgColor)
                ctx.setLineWidth(1.1)
                let cornerX: CGFloat = isLeft ? -13.5 : 13.5
                for k in 0..<2 {
                    let yy = -3.0 - CGFloat(k) * 3.4
                    ctx.move(to: CGPoint(x: cornerX, y: yy))
                    ctx.addLine(to: CGPoint(x: cornerX + (isLeft ? -3.6 : 3.6), y: yy - 2.0))
                }
                ctx.strokePath()
            }
            ctx.restoreGState()
            return
        }

        // Mode 1: Happy closed glowing lime-green curved line eyes (petting head!)
        if physics.isHappyClosedEyes {
            ctx.setStrokeColor(eyeColor.cgColor)
            ctx.setLineWidth(2.6)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: -11.5, y: 1.0))
            ctx.addQuadCurve(
                to: CGPoint(x: 11.5, y: 1.0),
                control: CGPoint(x: sign * 1.5, y: 3.4)
            )
            ctx.strokePath()
            ctx.restoreGState()
            return
        }

        // Mode 2: Blissful half-squint glowing lime slits (petting back/body!)
        if physics.isBlissfulSquint {
            ctx.setFillColor(eyeColor.cgColor)
            let slit = CGMutablePath()
            slit.move(to: CGPoint(x: -11.5, y: -0.5))
            slit.addQuadCurve(to: CGPoint(x: 11.5, y: -0.5), control: CGPoint(x: 0, y: 0.6))
            slit.addQuadCurve(to: CGPoint(x: -11.5, y: -0.5), control: CGPoint(x: 0, y: 4.8))
            slit.closeSubpath()
            ctx.addPath(slit)
            ctx.fillPath()
            ctx.restoreGState()
            return
        }

        let hunt = max(0, min(1, physics.huntIntensity.value))

        // Subtle feline eye angle (straightens slightly when wide-eyed hunting!)
        ctx.rotate(by: sign * (0.06 * (1.0 - hunt * 0.6)))

        // Eyes grow rounder & slightly larger in full hunting focus!
        let rx: CGFloat = 12.0 + hunt * 1.1
        let ry: CGFloat = 10.8 + hunt * 1.8
        let eyeRect = CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2)

        // Clip inside eye oval
        ctx.saveGState()
        ctx.addEllipse(in: eyeRect)
        ctx.clip()

        // Luminous chartreuse iris
        ctx.setFillColor(eyeColor.cgColor)
        ctx.fill(eyeRect)

        // Pupil morphs smoothly from vertical almond slit -> HUGE round black boba pupil when hunting!
        let gaze = physics.eyeGaze.point
        let px = gaze.x * (4.2 - hunt * 1.2)
        let py = gaze.y * (3.6 - hunt * 1.0)
        let pScale = physics.pupilScale.value
        let normalW: CGFloat = 5.0 * pScale
        let normalH: CGFloat = 13.5 * min(1.12, pScale)
        let huntDiameter: CGFloat = 18.8 // huge round boba pupil leaving an electric chartreuse ring!
        let pupilW = normalW + (huntDiameter - normalW) * hunt
        let pupilH = normalH + (huntDiameter - normalH) * hunt
        let pupilRect = CGRect(x: px - pupilW * 0.5, y: py - pupilH * 0.5, width: pupilW, height: pupilH)
        ctx.setFillColor(catBlack.cgColor)
        ctx.fillEllipse(in: pupilRect)

        // Tiny crisp white specular sparkle dot as hunting boba pupils dilate!
        if hunt > 0.25 {
            let glintAlpha = min(1.0, (hunt - 0.25) / 0.55) * 0.92
            ctx.setFillColor(NSColor(calibratedWhite: 1.0, alpha: glintAlpha).cgColor)
            let glintR: CGFloat = 2.1 + hunt * 0.9
            ctx.fillEllipse(in: CGRect(
                x: px - pupilW * 0.22 - glintR * 0.5,
                y: py - pupilH * 0.22 - glintR * 0.5,
                width: glintR * 2,
                height: glintR * 2
            ))
        }

        // Eyelid closure mask (matches black face or Siamese espresso mask!)
        let closure = physics.effectiveEyeClosure
        if closure > 0.02 {
            let lidHeight = (ry * 2.2) * closure
            ctx.setFillColor((isPointedCoat(coat) ? coatPoint(coat) : catBlack).cgColor)
            ctx.fill(CGRect(x: -rx - 2, y: -ry - 2, width: rx * 2 + 4, height: lidHeight))
        }

        ctx.restoreGState()
        ctx.restoreGState()
    }

    private static func drawWhiskers3D(
        in ctx: CGContext,
        yawRad: CGFloat,
        pitchRad: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let wiggle = sin(physics.time * 4.5) * (max(physics.petHeadIntensity, physics.petBodyIntensity) * 1.2)
        ctx.saveGState()
        let wColor = isPointedCoat(coat) ? coatWhisker(coat) : whiskerColor.withAlphaComponent(0.68)
        ctx.setStrokeColor(wColor.cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)

        // 3D cheek whiskers — when turning left, left whiskers naturally poke past silhouette
        // while right whiskers sweep inward across the cheek (exact Xiaohongshu effect!)
        for sign in [-1.0, 1.0] as [CGFloat] {
            let rows: [(CGFloat, CGFloat, CGFloat)] = [
                (10.5, 36.5, 8.8 + wiggle),
                (14.2, 37.8, 14.2 + wiggle * 0.5),
                (18.0, 35.5, 19.6 - wiggle * 0.4)
            ]
            for (y0, xEnd, yEnd) in rows {
                let p0 = projectHead3D(x: sign * 24.0, y: y0, z: 23.0, yawRad: yawRad, pitchRad: pitchRad).pt
                let p2 = projectHead3D(x: sign * xEnd, y: yEnd, z: 14.0, yawRad: yawRad, pitchRad: pitchRad).pt
                let ctrl = CGPoint(x: (p0.x + p2.x) * 0.5, y: (p0.y + p2.y) * 0.5 - 0.8)
                ctx.move(to: p0)
                ctx.addQuadCurve(to: p2, control: ctrl)
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Front Paws (Idle Sitting & Dynamic Reaching with Signature Outlines / Siamese Socks)

    private static func drawFrontPaws(
        in ctx: CGContext,
        seatX: CGFloat,
        seatY: CGFloat,
        breath: CGFloat,
        physics: CatPhysics,
        coat: CatCoatTheme
    ) {
        let lPos = physics.leftPaw.point
        let rPos = physics.rightPaw.point

        let lDist = hypot(lPos.x - CatPhysics.leftPawRest.x, lPos.y - CatPhysics.leftPawRest.y)
        let rDist = hypot(rPos.x - CatPhysics.rightPawRest.x, rPos.y - CatPhysics.rightPawRest.y)

        let leftShoulder = CGPoint(x: seatX - 24, y: seatY - 56 + breath)
        let rightShoulder = CGPoint(x: seatX + 24, y: seatY - 56 + breath)

        // Left arm
        if lDist < 6.0 && !physics.leftPawOnMouse && !physics.leftPawTyping {
            drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX - 18, y: seatY - 30), bottom: CGPoint(x: seatX - 16, y: seatY + 12), isLeft: true, coat: coat)
        } else {
            let mid = CGPoint(
                x: (leftShoulder.x + lPos.x) * 0.5 - (physics.leftPawOnMouse ? 8 : 4),
                y: (leftShoulder.y + lPos.y) * 0.5 - 6
            )
            drawLimb(
                in: ctx,
                start: leftShoulder,
                control: mid,
                end: lPos,
                startWidth: 19.0,
                endWidth: 13.5,
                outlineOnLeftSide: false,
                outlineAlpha: 0.78,
                coat: coat
            )
        }

        // Right arm
        if rDist < 6.0 && !physics.rightPawTyping {
            drawIdleFrontLeg(in: ctx, top: CGPoint(x: seatX + 18, y: seatY - 30), bottom: CGPoint(x: seatX + 16, y: seatY + 12), isLeft: false, coat: coat)
        } else {
            let mid = CGPoint(
                x: (rightShoulder.x + rPos.x) * 0.5 + 4,
                y: (rightShoulder.y + rPos.y) * 0.5 - 6
            )
            drawLimb(
                in: ctx,
                start: rightShoulder,
                control: mid,
                end: rPos,
                startWidth: 19.0,
                endWidth: 13.5,
                outlineOnLeftSide: true,
                outlineAlpha: 0.78,
                coat: coat
            )
        }
    }

    /// Signature tucked sitting front legs (black with mint lines OR Siamese cream-to-chocolate socks!)
    private static func drawIdleFrontLeg(in ctx: CGContext, top: CGPoint, bottom: CGPoint, isLeft: Bool, coat: CatCoatTheme) {
        let sign: CGFloat = isLeft ? -1.0 : 1.0
        ctx.saveGState()

        if isPointedCoat(coat) {
            // Creamy upper leg dipping smoothly into adorable seal-point chocolate socks at the bottom!
            let legRect = CGRect(x: bottom.x - 7.5, y: top.y, width: 15.0, height: bottom.y - top.y + 1.0)
            let legPath = CGPath(roundedRect: legRect, cornerWidth: 6.5, cornerHeight: 6.5, transform: nil)
            ctx.saveGState()
            ctx.addPath(legPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                coatCream(coat).withAlphaComponent(0.0).cgColor,
                coatMocha(coat).withAlphaComponent(0.75).cgColor,
                coatPoint(coat).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.05, 0.52, 0.85]) {
                ctx.drawLinearGradient(
                    grad,
                    start: CGPoint(x: top.x, y: top.y),
                    end: CGPoint(x: bottom.x, y: bottom.y + 2),
                    options: []
                )
            }
            ctx.restoreGState()
        }

        let lineColor = isPointedCoat(coat) ? coatOutline(coat).withAlphaComponent(0.62) : contourMint
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(1.45)
        ctx.setLineCap(.round)

        // Outer separation crease
        ctx.move(to: CGPoint(x: top.x + sign * 8.5, y: top.y))
        ctx.addQuadCurve(
            to: CGPoint(x: bottom.x + sign * 7.5, y: bottom.y - 1),
            control: CGPoint(x: top.x + sign * 9.5, y: (top.y + bottom.y) * 0.5)
        )
        // Inner separation crease
        ctx.move(to: CGPoint(x: top.x - sign * 7.0, y: top.y + 4))
        ctx.addQuadCurve(
            to: CGPoint(x: bottom.x - sign * 6.0, y: bottom.y - 1),
            control: CGPoint(x: top.x - sign * 6.5, y: (top.y + bottom.y) * 0.5)
        )
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Smooth tapered limb + plump rounded paw (matte black OR Siamese cream-to-espresso chocolate socks!)
    private static func drawLimb(
        in ctx: CGContext,
        start: CGPoint,
        control: CGPoint,
        end: CGPoint,
        startWidth: CGFloat,
        endWidth: CGFloat,
        outlineOnLeftSide: Bool,
        outlineAlpha: CGFloat,
        coat: CatCoatTheme
    ) {
        let steps = 14
        var leftEdge: [CGPoint] = []
        var rightEdge: [CGPoint] = []

        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = quadPoint(start, control, end, t: t)
            let tan = quadTangent(start, control, end, t: t)
            let len = max(0.001, hypot(tan.x, tan.y))
            let nx = -tan.y / len
            let ny = tan.x / len
            let halfW = (startWidth + (endWidth - startWidth) * t) * 0.5
            leftEdge.append(CGPoint(x: p.x + nx * halfW, y: p.y + ny * halfW))
            rightEdge.append(CGPoint(x: p.x - nx * halfW, y: p.y - ny * halfW))
        }

        let limbPath = CGMutablePath()
        limbPath.move(to: leftEdge[0])
        for pt in leftEdge.dropFirst() { limbPath.addLine(to: pt) }
        for pt in rightEdge.reversed() { limbPath.addLine(to: pt) }
        limbPath.closeSubpath()

        let pawR = endWidth * 0.58
        let pawRect = CGRect(x: end.x - pawR, y: end.y - pawR * 0.85, width: pawR * 2, height: pawR * 1.7)

        ctx.saveGState()
        if coat == .classicBlack {
            ctx.setFillColor(catBlack.cgColor)
            ctx.addPath(limbPath)
            ctx.fillPath()
            ctx.fillEllipse(in: pawRect)
        } else {
            // Siamese chocolate-dipped socks gradient along the limb!
            // Starts transparent at shoulder (0.0) so it melts 100% seamlessly into the creamy chest!
            ctx.saveGState()
            ctx.addPath(limbPath)
            ctx.clip()
            let cs = CGColorSpaceCreateDeviceRGB()
            let colors = [
                coatCream(coat).withAlphaComponent(0.0).cgColor,
                coatCream(coat).cgColor,
                coatMocha(coat).cgColor,
                coatPoint(coat).cgColor
            ] as CFArray
            if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.0, 0.16, 0.48, 0.78]) {
                ctx.drawLinearGradient(grad, start: start, end: end, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()

            // Solid rich espresso-chocolate rounded paw tip (no winding-rule overlap artifacts!)
            ctx.setFillColor(coatPoint(coat).cgColor)
            ctx.fillEllipse(in: pawRect)

            // Clean outer edge outline on Siamese arm (fading in below shoulder) so it reads crisply over light backgrounds
            ctx.setStrokeColor(coatOutline(coat).withAlphaComponent(0.72).cgColor)
            ctx.setLineWidth(1.25)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let outerEdge = outlineOnLeftSide ? rightEdge : leftEdge
            if outerEdge.count > 4 {
                ctx.move(to: outerEdge[3])
                for idx in 4..<(outerEdge.count - 1) { ctx.addLine(to: outerEdge[idx]) }
                ctx.strokePath()
            }
        }

        // Crisp separation stroke along upper-to-mid arm where it crosses the torso
        let highlightEdge = outlineOnLeftSide ? leftEdge : rightEdge
        if highlightEdge.count > 6 {
            let strokeColor = isPointedCoat(coat)
                ? coatOutline(coat).withAlphaComponent(outlineAlpha * 0.78)
                : contourMint.withAlphaComponent(outlineAlpha * 0.9)
            ctx.setStrokeColor(strokeColor.cgColor)
            ctx.setLineWidth(1.35)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let startIdx = 2
            let endIdx = Int(CGFloat(highlightEdge.count - 1) * 0.68)
            ctx.move(to: highlightEdge[startIdx])
            for idx in (startIdx + 1)...endIdx {
                ctx.addLine(to: highlightEdge[idx])
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    // MARK: - Floating Mechanical Keycap Popups

    private static func drawFloatingKeycaps(in ctx: CGContext, physics: CatPhysics) {
        for badge in physics.floatingKeycaps {
            let progress = badge.age / badge.lifetime
            // Spring pop-in scale (starts crisp and readable immediately!)
            let scale: CGFloat
            if badge.age < 0.09 {
                let t = badge.age / 0.09
                scale = 0.72 + 0.38 * sin(t * .pi * 0.65)
            } else if badge.age < 0.18 {
                let t = (badge.age - 0.09) / 0.09
                scale = 1.10 - 0.10 * t
            } else {
                scale = 1.0
            }

            let alpha: CGFloat = progress < 0.62 ? 1.0 : max(0, 1.0 - (progress - 0.62) / 0.38)

            let charCount = badge.label.count
            let w: CGFloat = charCount <= 1 ? 23 : (charCount == 2 ? 30 : 38)
            let h: CGFloat = 22

            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.translateBy(x: badge.position.x, y: badge.position.y)
            ctx.rotate(by: badge.rotation)
            ctx.scaleBy(x: scale, y: scale)

            // 3D bottom keycap edge / shadow
            let baseRect = CGRect(x: -w * 0.5, y: -h * 0.5 + 2.5, width: w, height: h)
            let basePath = CGPath(roundedRect: baseRect, cornerWidth: 5.5, cornerHeight: 5.5, transform: nil)
            ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.15, blue: 0.17, alpha: 0.95).cgColor)
            ctx.addPath(basePath)
            ctx.fillPath()

            // Crisp white mechanical keycap top face
            let faceRect = CGRect(x: -w * 0.5, y: -h * 0.5, width: w, height: h)
            let facePath = CGPath(roundedRect: faceRect, cornerWidth: 5.2, cornerHeight: 5.2, transform: nil)
            ctx.setFillColor(NSColor(calibratedRed: 0.975, green: 0.972, blue: 0.952, alpha: 1.0).cgColor)
            ctx.addPath(facePath)
            ctx.fillPath()

            ctx.setStrokeColor(NSColor(calibratedRed: 0.16, green: 0.16, blue: 0.18, alpha: 1.0).cgColor)
            ctx.setLineWidth(1.45)
            ctx.addPath(facePath)
            ctx.strokePath()

            // Centered bold key label
            let fontSize: CGFloat = charCount <= 1 ? 11.5 : 10.0
            let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1.0)
            ]
            let attrStr = NSAttributedString(string: badge.label, attributes: attrs)
            let strSize = attrStr.size()
            let drawPt = CGPoint(x: -strSize.width * 0.5, y: -strSize.height * 0.5 - 0.5)
            NSGraphicsContext.saveGraphicsState()
            let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
            NSGraphicsContext.current = nsCtx
            attrStr.draw(at: drawPt)
            NSGraphicsContext.restoreGraphicsState()

            ctx.restoreGState()
        }
    }

    // MARK: - Subtle Petting Sparkles & Sleep Z

    private static func drawSparkles(in ctx: CGContext, physics: CatPhysics, eyeTheme: EyeColorTheme) {
        for sp in physics.sparkles {
            let p = sp.age / sp.lifetime
            let alpha = sin(min(1.0, p) * .pi)
            ctx.saveGState()
            ctx.setAlpha(alpha * 0.85)
            if sp.isSleepZ {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11 + p * 3, weight: .bold),
                    .foregroundColor: eyeTheme.primaryColor
                ]
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
                NSAttributedString(string: "z", attributes: attrs).draw(at: sp.position)
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // Tiny glowing chartreuse 4-point star
                let r: CGFloat = 3.5 + p * 1.5
                ctx.translateBy(x: sp.position.x, y: sp.position.y)
                ctx.setFillColor(eyeTheme.primaryColor.cgColor)
                let star = CGMutablePath()
                star.move(to: CGPoint(x: 0, y: -r))
                star.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0.8, y: -0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: 0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -0.8, y: 0.8))
                star.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: -0.8, y: -0.8))
                star.closeSubpath()
                ctx.addPath(star)
                ctx.fillPath()
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Overload Smoke (rising wisps above the head)

    private static func drawSmoke(in ctx: CGContext, physics: CatPhysics) {
        guard !physics.smokePuffs.isEmpty else { return }
        // Manga-style "steam" — thin curling line wisps rising off the head,
        // some ending in a little spiral curl, instead of solid grey blobs.
        let ink = NSColor(calibratedRed: 0.34, green: 0.37, blue: 0.40, alpha: 1.0)
        for puff in physics.smokePuffs {
            let p = min(1, puff.age / puff.lifetime)
            let alpha = sin(min(1, p * 1.1) * .pi) * 0.62 * (1 - p * 0.25)
            guard alpha > 0.01 else { continue }

            ctx.saveGState()
            ctx.setStrokeColor(ink.withAlphaComponent(alpha).cgColor)
            ctx.setLineWidth(1.6 + p * 0.7)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let len: CGFloat = 15 + p * 15 + puff.radius * 0.5
            let amp: CGFloat = 4.2 + p * 3.2
            let sway = sin(p * 3.6 + puff.seed) * 2.6
            let x0 = puff.position.x + sway
            let y0 = puff.position.y
            let topX = x0 + sin(puff.seed) * amp

            // Rising S-curve wisp (negative y = up in the logical canvas).
            let wisp = CGMutablePath()
            wisp.move(to: CGPoint(x: x0, y: y0 + len * 0.5))
            wisp.addCurve(
                to: CGPoint(x: topX, y: y0 - len * 0.5),
                control1: CGPoint(x: x0 - amp, y: y0 + len * 0.12),
                control2: CGPoint(x: x0 + amp, y: y0 - len * 0.12)
            )
            ctx.addPath(wisp)
            ctx.strokePath()

            // About half the wisps end in a tightening spiral curl.
            if puff.seed > 3.1 {
                let spiral = CGMutablePath()
                var ang: CGFloat = 0
                var rad: CGFloat = 4.2 + p * 1.2
                spiral.move(to: CGPoint(x: topX + rad, y: y0 - len * 0.5))
                for _ in 0..<20 {
                    ang += 0.5
                    rad *= 0.90
                    spiral.addLine(to: CGPoint(x: topX + cos(ang) * rad,
                                               y: y0 - len * 0.5 + sin(ang) * rad))
                }
                ctx.addPath(spiral)
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
    }

    // MARK: - Non-Intrusive Permission Pill

    private static func drawPermissionPill(in ctx: CGContext) {
        let r = permissionPillRect
        let path = CGPath(roundedRect: r, cornerWidth: 11, cornerHeight: 11, transform: nil)

        ctx.saveGState()
        ctx.setFillColor(NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 0.90).cgColor)
        ctx.addPath(path)
        ctx.fillPath()

        ctx.setStrokeColor(NSColor(calibratedRed: 0.79, green: 0.95, blue: 0.25, alpha: 0.90).cgColor)
        ctx.setLineWidth(1.2)
        ctx.addPath(path)
        ctx.strokePath()

        let text = "点击开启全局/游戏键盘监听 🔑"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: NSColor(calibratedRed: 0.95, green: 0.97, blue: 0.90, alpha: 1.0)
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        str.draw(at: CGPoint(x: r.midX - sz.width * 0.5, y: r.midY - sz.height * 0.5 - 0.5))
        NSGraphicsContext.restoreGraphicsState()

        ctx.restoreGState()
    }

    // MARK: - Geometry & Color Helpers

    private static func offsetY(_ pt: CGPoint, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: pt.x, y: pt.y + dy)
    }

    private static func quadPoint(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: mt * mt * p0.x + 2 * mt * t * p1.x + t * t * p2.x,
            y: mt * mt * p0.y + 2 * mt * t * p1.y + t * t * p2.y
        )
    }

    private static func quadTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, t: CGFloat) -> CGPoint {
        let mt = 1 - t
        return CGPoint(
            x: 2 * mt * (p1.x - p0.x) + 2 * t * (p2.x - p1.x),
            y: 2 * mt * (p1.y - p0.y) + 2 * t * (p2.y - p1.y)
        )
    }

    private static func roundedQuadPath(
        tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint, radius: CGFloat
    ) -> CGPath {
        let p = CGMutablePath()
        let midTop = CGPoint(x: (tl.x + tr.x) * 0.5, y: (tl.y + tr.y) * 0.5)
        p.move(to: midTop)
        p.addArc(tangent1End: tr, tangent2End: br, radius: radius)
        p.addArc(tangent1End: br, tangent2End: bl, radius: radius)
        p.addArc(tangent1End: bl, tangent2End: tl, radius: radius)
        p.addArc(tangent1End: tl, tangent2End: tr, radius: radius)
        p.closeSubpath()
        return p
    }

    private static func blendColor(_ a: NSColor, _ b: NSColor, t: CGFloat) -> NSColor {
        let ca = a.usingColorSpace(.deviceRGB) ?? a
        let cb = b.usingColorSpace(.deviceRGB) ?? b
        let clamped = max(0, min(1, t))
        return NSColor(
            calibratedRed: ca.redComponent + (cb.redComponent - ca.redComponent) * clamped,
            green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * clamped,
            blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * clamped,
            alpha: ca.alphaComponent + (cb.alphaComponent - ca.alphaComponent) * clamped
        )
    }

    private static func drawRadialGlow(in ctx: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [color.cgColor, color.withAlphaComponent(0.0).cgColor] as CFArray
        let locs: [CGFloat] = [0.0, 1.0]
        if let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locs) {
            ctx.saveGState()
            ctx.drawRadialGradient(
                grad,
                startCenter: center, startRadius: 0,
                endCenter: center, endRadius: radius,
                options: []
            )
            ctx.restoreGState()
        }
    }
}

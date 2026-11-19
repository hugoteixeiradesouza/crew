import Foundation
import CoreGraphics
import AppKit
import SwiftUI

// MARK: - Glifos do selo ("!" e "?"), em contorno, para tamanho de fonte 1 e centrados na origem

enum Glifo {
    static let exclamacao = contorno("!")
    static let interrogacao = contorno("?")

    private static func contorno(_ c: String) -> Path {
        let fonte = NSFont.systemFont(ofSize: 1, weight: .black) as CTFont
        var unidades = Array(c.utf16)
        var glifos = [CGGlyph](repeating: 0, count: unidades.count)
        guard CTFontGetGlyphsForCharacters(fonte, &unidades, &glifos, unidades.count),
              let cg = CTFontCreatePathForGlyph(fonte, glifos[0], nil) else { return Path() }
        // CoreText tem y para cima; o Canvas, para baixo. Centra pela caixa do glifo.
        let b = cg.boundingBoxOfPath
        var t = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: -b.midX, y: -b.midY)
        return Path(cg.copy(using: &t) ?? cg)
    }
}

// MARK: - Easing functions (same as prototype: E.out, E.inOut, E.back, E.lin)

enum Ease {
    static func out(_ t: CGFloat) -> CGFloat   { 1 - pow(1 - t, 3) }
    static func inOut(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4*t*t*t : 1 - pow(-2*t+2, 3)/2 }
    static func back(_ t: CGFloat) -> CGFloat  { let c1: CGFloat = 1.7; let c3 = c1+1; return 1+c3*pow(t-1,3)+c1*pow(t-1,2) }
    static func lin(_ t: CGFloat) -> CGFloat   { t }
}

// MARK: - Tween key: [target, duration_ms, easing]

struct TweenKey {
    let target: CGFloat
    let duration: CGFloat    // milliseconds
    let ease: (CGFloat) -> CGFloat
}

struct Tween {
    let property: String
    var keys: [TweenKey]
    var keyIndex: Int = 0
    var from: CGFloat
    var startTime: Double    // CACurrentMediaTime() * 1000
    var onComplete: (() -> Void)? = nil
}

// MARK: - Particle

struct Particle {
    enum ParticleType { case heart, star, spark, sweat, z, nota }
    var type: ParticleType
    var x, y, vx, vy: CGFloat
    var age: Double        // seconds
    var life: Double
    var rot: CGFloat
    var size: CGFloat
}

// MARK: - Bot state config (mirrors STATES in prototype)

struct BotStateCfg {
    let color: CGColor
    let tint: CGFloat
    let eye: EyeShape
    let badge: BadgeType?
    let badgeColor: CGColor
    let glow: CGColor
    let glowOpacity: CGFloat
    let bounces: Bool
    let scans: Bool
    let breathes: Bool
    let zz: Bool
    let sweat: Bool
    let look: CGPoint?     // fixed look direction
    let tilt: CGFloat
    let sound: String?
}

enum EyeShape: String {
    case pill, wide, dot, line, flat, happy, closed, spiral, heart, star, tired, wink, cup, x
    /// Olhos apertados "> <" (som alto demais, tela forte demais)
    case aperto
    /// Olhos fechados em arco "^ ^", curtindo o som
    case curtindo
}

/// Ajustes de aparência do Homie (o desenho em si: HomieCorpo.swift e HomieBone.swift).
enum BotStyle {
    nonisolated(unsafe) static var brows = false
    nonisolated(unsafe) static var cap = true
    /// Cor do boné (r, g, b)
    nonisolated(unsafe) static var capRGB: (Double, Double, Double) = (0.17, 0.18, 0.20)
    /// Aba reta: 0 = para o lado (na base), 1 = para a frente (aba reta clássica)
    nonisolated(unsafe) static var brimForward = false
    /// Contorno de nanquim no corpo e no boné (o boné de tecido não tem traço sem ele)
    nonisolated(unsafe) static var outline = false
    /// AirPods Max: false = cinza-espacial, true = prata
    nonisolated(unsafe) static var phonesSilver = false
    /// true = AirPods Pro 3 (intra-auriculares); false = AirPods Max
    nonisolated(unsafe) static var earbuds = true
    /// Cor principal do corpo (r, g, b); nil = o branco de sempre
    nonisolated(unsafe) static var corBase: (Double, Double, Double)? = nil
}

enum BadgeType {
    case dots(CGColor)
    case bang(CGColor)
    case question(CGColor)
    case dot(CGColor)
}

// MARK: - Homie track constants (from PISTES.mochi)

enum BotConst {
    static let eyeW: CGFloat  = 0.25
    static let eyeH: CGFloat  = 0.27
    static let eyeSp: CGFloat = 0.37
    static let eyeP: CGFloat  = -0.12
    /// Corpo: degradê do topo (claro) à base (escura). Personalizável pela cor principal.
    static var baseTop: CGColor {
        guard let c = BotStyle.corBase else { return CGColor(red: 0.929, green: 0.929, blue: 0.937, alpha: 1) }  // #EDEDEF
        return CGColor(red: c.0 + (1 - c.0) * 0.28, green: c.1 + (1 - c.1) * 0.28, blue: c.2 + (1 - c.2) * 0.28, alpha: 1)
    }
    static var baseBottom: CGColor {
        guard let c = BotStyle.corBase else { return CGColor(red: 0.769, green: 0.773, blue: 0.792, alpha: 1) }  // #C4C5CA
        return CGColor(red: c.0 * 0.80, green: c.1 * 0.80, blue: c.2 * 0.82, alpha: 1)
    }
    /// Tinta dos olhos e das sobrancelhas
    static let ink        = CGColor(red: 0.086, green: 0.078, blue: 0.094, alpha: 1)  // #161418
    static let miniInk    = CGColor(red: 0.063, green: 0.075, blue: 0.102, alpha: 1)  // #10131A
}

// MARK: - Bot state configs

let BotStates: [BotState: BotStateCfg] = [
    .idle: BotStateCfg(
        color: CGColor(red:0.902,green:0.914,blue:0.933,alpha:1), tint:0,
        eye:.pill, badge:nil,
        badgeColor: .white, glow: CGColor(red:1,green:1,blue:1,alpha:0.35), glowOpacity:0.25,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:nil),
    .working: BotStateCfg(
        color: CGColor(red:0.231,green:0.620,blue:1,alpha:1), tint:0.72,
        eye:.pill, badge:.dots(CGColor(red:0.231,green:0.620,blue:1,alpha:1)),
        badgeColor: CGColor(red:0.231,green:0.620,blue:1,alpha:1),
        glow: CGColor(red:0.231,green:0.620,blue:1,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"work"),
    .thinking: BotStateCfg(
        color: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1), tint:0.72,
        eye:.pill, badge:.dots(CGColor(red:0.545,green:0.361,blue:0.965,alpha:1)),
        badgeColor: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1),
        glow: CGColor(red:0.545,green:0.361,blue:0.965,alpha:1), glowOpacity:0.5,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look: CGPoint(x:0.55, y:0.55), tilt:0, sound:"think"),
    .searching: BotStateCfg(
        color: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1), tint:0.72,
        eye:.pill, badge:.dots(CGColor(red:0.388,green:0.396,blue:0.949,alpha:1)),
        badgeColor: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1),
        glow: CGColor(red:0.388,green:0.396,blue:0.949,alpha:1), glowOpacity:0.55,
        bounces:false, scans:true, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"search"),
    .approval: BotStateCfg(
        color: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1), tint:0.78,
        eye:.wide, badge:.bang(CGColor(red:0.961,green:0.647,blue:0.141,alpha:1)),
        badgeColor: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1),
        glow: CGColor(red:0.961,green:0.647,blue:0.141,alpha:1), glowOpacity:0.6,
        bounces:true, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"approval"),
    .question: BotStateCfg(
        color: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1), tint:0.75,
        eye:.pill, badge:.question(CGColor(red:0.133,green:0.827,blue:0.933,alpha:1)),
        badgeColor: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1),
        glow: CGColor(red:0.133,green:0.827,blue:0.933,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0.17, sound:"question"),
    .error: BotStateCfg(
        color: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1), tint:0.78,
        eye:.flat, badge:.dot(CGColor(red:0.957,green:0.314,blue:0.369,alpha:1)),
        badgeColor: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1),
        glow: CGColor(red:0.957,green:0.314,blue:0.369,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"error"),
    .finished: BotStateCfg(
        color: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1), tint:0.35,
        eye:.happy, badge:.dot(CGColor(red:0.204,green:0.831,blue:0.600,alpha:1)),
        badgeColor: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1),
        glow: CGColor(red:0.204,green:0.831,blue:0.600,alpha:1), glowOpacity:0.5,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"finish"),
    .ratelimit: BotStateCfg(
        color: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1), tint:0.72,
        eye:.tired, badge:.dot(CGColor(red:0.984,green:0.573,blue:0.235,alpha:1)),
        badgeColor: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1),
        glow: CGColor(red:0.984,green:0.573,blue:0.235,alpha:1), glowOpacity:0.45,
        bounces:false, scans:false, breathes:false, zz:false, sweat:true,
        look:nil, tilt:0, sound:"rate"),
    .sleeping: BotStateCfg(
        color: CGColor(red:0.580,green:0.635,blue:0.722,alpha:1), tint:0.32,
        eye:.closed, badge:nil,
        badgeColor: .white,
        glow: CGColor(red:0.580,green:0.635,blue:0.722,alpha:1), glowOpacity:0.2,
        bounces:false, scans:false, breathes:true, zz:true, sweat:false,
        look:nil, tilt:0, sound:"sleep"),
    .dizzy: BotStateCfg(
        color: CGColor(red:0.957,green:0.447,blue:0.714,alpha:1), tint:0.7,
        eye:.spiral, badge:nil,
        badgeColor: .white,
        glow: CGColor(red:0.957,green:0.447,blue:0.714,alpha:1), glowOpacity:0.55,
        bounces:false, scans:false, breathes:false, zz:false, sweat:false,
        look:nil, tilt:0, sound:"dizzy"),
]

// MARK: - Bot engine

@MainActor
final class BotEngine: ObservableObject {
    var isMini: Bool = false
    var bodyColor: CGColor? = nil    // override for mini bots
    /// Guardados entre quadros (ver HomieCorpo.swift e HomieBone.swift): degradês do corpo na
    /// cor atual e geometria do boné no tamanho/giro atual.
    var tonsCorpo: TonsDoCorpo?
    var formaBone: FormaBone?
    /// Fone de ouvido enquanto toca música (entra e sai animado).
    var headphonesOn = false
    private var headphonesAmt: CGFloat = 0

    /// Brilho/volume mudando: celular na mão (brilho) ou fones (volume), reagindo ao nível.
    enum NivelProp { case nenhum, celular, fones }
    var nivelProp: NivelProp = .nenhum
    /// Nível atual (0…1); 0 no volume = mudo.
    var nivelValor: CGFloat = 0.5
    private var celularAmt: CGFloat = 0
    private var nivelVis: CGFloat = 0.5
    /// Pulo a cada mudança: + subiu, − desceu (decai sozinho)
    private var nivelPulo: CGFloat = 0
    private var nivelAnterior: CGFloat = -1
    private var notaAcumulada: Double = 0
    /// Tamanho dos olhos pela reação (arregala no baixinho/escuro)
    private var nivelEs: CGFloat = 1

    // Animation state (mirrors prototype 's' object)
    var yaw:    CGFloat = 0
    var pitch:  CGFloat = 0
    var roll:   CGFloat = 0
    var tilt:   CGFloat = 0
    var open:   CGFloat = 1          // eye open amount
    var sx:     CGFloat = 1          // scale X
    var sy:     CGFloat = 1          // scale Y
    var oy:     CGFloat = 0          // offset Y (bounce)
    var ox:     CGFloat = 0          // offset X (shake)
    var tint:   CGFloat = 0
    var morph:  CGFloat = 0          // morph to rect (for upload bucket)
    var hands:  CGFloat = 0
    var blush:  CGFloat = 0
    var es:     CGFloat = 1          // eye scale
    var badgeS: CGFloat = 0          // badge scale

    // Targets
    var tgYaw:    CGFloat = 0
    var tgPitch:  CGFloat = 0
    var tgTilt:   CGFloat = 0
    var tgSy:     CGFloat = 1
    var tgSx:     CGFloat = 1
    var tgEs:     CGFloat = 1   // eye-scale target (hover love: 1.08, normal: 1)

    // Particle canvas overhang (extra canvas height at top for hearts to fly into)
    var particleOverhang: CGFloat = 0

    // Mouth spring (fraction of R: 0=closed, 0.20=hover, 0.42=open, 0.50=overopen)
    var slotH: CGFloat = 0           // current height (fraction of R)
    var slotHTarget: CGFloat = 0     // spring target
    var slotHVel: CGFloat = 0        // spring velocity (fraction of R / s)
    var isChewing: Bool = false       // true for ~800ms after gulp swallow

    // Color (animated)
    var col:  (CGFloat, CGFloat, CGFloat) = (0.902, 0.914, 0.933)  // idle
    var colT: (CGFloat, CGFloat, CGFloat) = (0.902, 0.914, 0.933)

    // State
    var state: BotState = .idle
    var cfg: BotStateCfg = BotStates[.idle]!

    // Eye override (emote)
    var eyeOverride: EyeShape? = nil
    var eyeOverrideUntil: Double = 0   // CACurrentMediaTime()
    var permanentEye: EyeShape? = nil   // restored after temporary emote/blink expires
    var permanentEmote: BotEmote? = nil // stored so doMiniBehaviorLoop can switch on it
    var miniNextBehavior: Double = 0    // CACurrentMediaTime() of next periodic mini action

    // Badge animation
    var badge: BadgeType? = nil
    var badgeKey: String = "none"
    var badgeToken: Int = 0

    // Tweens (keyed by property name)
    var tweens: [String: Tween] = [:]
    var locks:  Set<String> = []

    // Particles
    var particles: [Particle] = []

    // Look target
    var lookX: CGFloat = 0
    var lookY: CGFloat = 0

    // Timing
    var lastTime: Double = CACurrentMediaTime()
    var t0: Double = CACurrentMediaTime() - Double.random(in: 0...5)
    var nextBlink: Double = CACurrentMediaTime() + 1.5 + Double.random(in: 0...2)
    var waveUntil: Double = 0
    var waveStart: Double = 0     // CACurrentMediaTime() when wave animation began
    var greetToken: Int = 0       // incremented to invalidate stale greet closures
    var lastAmbient: Double = 0

    // Slap tracking (for dizzy on 3 slaps)
    var slapTimes: [Double] = []

    // Mini wandering look (random, ignores mouse)
    var miniLookTarget: CGPoint = .zero
    var miniLookNextTime: Double = 0

    // MARK: - Public API

    func setState(_ newState: BotState, force: Bool = false) {
        guard state != newState || force else { return }
        let prev = state
        state = newState
        cfg = BotStates[newState]!
        colT = cgColorToTuple(cfg.color)
        setTarget(key: "tint", value: cfg.tint)
        setTarget(key: "tilt", value: cfg.tilt)
        setBadge(cfg.badge)

        switch newState {
        case .finished:
            doRoll(duration: 950, turns: 1)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.emit(.spark, count: 5)
            }
        case .error:
            anim("ox", keys: [
                TweenKey(target: 0.08,  duration: 50,  ease: Ease.out),
                TweenKey(target: -0.08, duration: 70,  ease: Ease.inOut),
                TweenKey(target: 0.05,  duration: 70,  ease: Ease.inOut),
                TweenKey(target: 0,     duration: 90,  ease: Ease.out),
            ])
        case .approval:
            anim("oy", keys: [
                TweenKey(target: -0.2, duration: 150, ease: Ease.out),
                TweenKey(target: 0,    duration: 300, ease: Ease.back),
            ])
        case .dizzy:
            doRoll(duration: 1300, turns: 2)
        case .question:
            blink()
        case .ratelimit:
            emit(.sweat, count: 1)
        default:
            if prev != .idle || newState != .idle { blink() }
        }
    }

    func setBadge(_ b: BadgeType?) {
        let key = badgeString(b)
        guard key != badgeKey else { return }
        badgeKey = key
        let tok = badgeToken + 1
        badgeToken = tok
        anim("badgeS", keys: [TweenKey(target: 0, duration: 90, ease: Ease.inOut)])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, tok == self.badgeToken else { return }
            self.badge = b
            if b != nil {
                self.anim("badgeS", keys: [TweenKey(target: 1, duration: 280, ease: Ease.back)])
            }
        }
    }

    func blink() {
        guard !locks.contains("open") else { return }
        anim("open", keys: [
            TweenKey(target: 0.06, duration: 70,  ease: Ease.inOut),
            TweenKey(target: 1,    duration: 130, ease: Ease.out),
        ])
    }

    func squash() {
        anim("sy", keys: [
            TweenKey(target: 0.78, duration: 70,  ease: Ease.out),
            TweenKey(target: 1.1,  duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
        anim("sx", keys: [
            TweenKey(target: 1.16, duration: 70,  ease: Ease.out),
            TweenKey(target: 0.95, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 170, ease: Ease.inOut),
        ])
    }

    // MARK: - Gulp (mailbox swallow)

    func gulp() {
        // Open mouth wide for the swallow, then close during chewing
        slotHTarget = 0.42
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) { [weak self] in
            self?.slotHTarget = 0
            self?.isChewing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.80) { [weak self] in
                self?.isChewing = false
            }
        }
        anim("sy", keys: [
            TweenKey(target: 0.78, duration: 80,  ease: Ease.out),
            TweenKey(target: 1.18, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        anim("sx", keys: [
            TweenKey(target: 1.28, duration: 80,  ease: Ease.out),
            TweenKey(target: 0.92, duration: 130, ease: Ease.out),
            TweenKey(target: 1,    duration: 220, ease: Ease.back),
        ])
        blink()
    }

    // MARK: - Slap (dizzy mechanic)

    func slap() {
        interruptGreet()
        guard state != .dizzy else { return }
        let now = CACurrentMediaTime()
        slapTimes = slapTimes.filter { now - $0 < 1.7 }
        slapTimes.append(now)
        SoundEngine.shared.play("slap")
        squash()
        if slapTimes.count >= 3 {
            slapTimes = []
            NotificationCenter.default.post(name: .botDizzy, object: nil)
        } else {
            // Annoyed: line eyes for 800ms, annoyed sound after 60ms delay
            eyeOverride = .line
            eyeOverrideUntil = now + 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                SoundEngine.shared.play("annoyed")
            }
        }
    }

    // MARK: - Mini periodic behavior loop

    func doMiniBehaviorLoop() {
        switch permanentEmote {

        case .happy:
            // Little jump + squash
            guard !locks.contains("oy") else {
                miniNextBehavior = CACurrentMediaTime() + 0.4
                return
            }
            anim("oy", keys: [
                TweenKey(target: -0.30, duration: 120, ease: Ease.out),
                TweenKey(target:  0.03, duration: 200, ease: Ease.inOut),
                TweenKey(target:  0,    duration: 160, ease: Ease.back),
            ])
            anim("sy", keys: [
                TweenKey(target: 0.82, duration: 80,  ease: Ease.out),
                TweenKey(target: 1.18, duration: 130, ease: Ease.out),
                TweenKey(target: 0.88, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            anim("sx", keys: [
                TweenKey(target: 1.15, duration: 80,  ease: Ease.out),
                TweenKey(target: 0.88, duration: 130, ease: Ease.out),
                TweenKey(target: 1.06, duration: 160, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 200, ease: Ease.back),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...1.2)

        case .annoyed:
            // Rapid head shake
            guard !locks.contains("yaw") else {
                miniNextBehavior = CACurrentMediaTime() + 0.5
                return
            }
            anim("yaw", keys: [
                TweenKey(target: -0.65, duration: 50,  ease: Ease.out),
                TweenKey(target:  0.65, duration: 90,  ease: Ease.inOut),
                TweenKey(target: -0.5,  duration: 80,  ease: Ease.inOut),
                TweenKey(target:  0.4,  duration: 75,  ease: Ease.inOut),
                TweenKey(target: -0.2,  duration: 70,  ease: Ease.inOut),
                TweenKey(target:  0,    duration: 140, ease: Ease.out),
            ])
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.5)

        case .wink:
            // Brief wink: eye closes, head tilts slightly
            let now2 = CACurrentMediaTime()
            eyeOverride = .wink
            eyeOverrideUntil = now2 + 0.55
            anim("tilt", keys: [
                TweenKey(target:  0.13, duration: 100, ease: Ease.out),
                TweenKey(target:  0.13, duration: 320, ease: Ease.lin),
                TweenKey(target:  0,    duration: 200, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.2 + Double.random(in: 0...2.0)

        case .love:
            // Grafite: sem corações — só o balanço
            anim("tilt", keys: [
                TweenKey(target: -0.1, duration: 180, ease: Ease.out),
                TweenKey(target:  0.1, duration: 340, ease: Ease.inOut),
                TweenKey(target:  0,   duration: 220, ease: Ease.inOut),
            ])
            miniNextBehavior = CACurrentMediaTime() + 2.6 + Double.random(in: 0...1.5)

        default:
            miniNextBehavior = CACurrentMediaTime() + 3.0 + Double.random(in: 0...2.0)
        }
    }

    func doRoll(duration: CGFloat, turns: CGFloat) {
        roll = 0
        anim("roll", keys: [TweenKey(target: .pi * 2 * turns, duration: duration, ease: Ease.inOut)]) { [weak self] in
            self?.roll = 0
        }
    }

    func greet() {
        let now = CACurrentMediaTime()
        greetToken += 1
        let tok = greetToken
        waveStart = now + 0.45   // wave begins at 0.45s
        waveUntil = now + 1.55   // wave ends at 1.55s

        // 0s: happy eyes for full greeting (2s — no gap, no flicker)
        eyeOverride = .happy
        eyeOverrideUntil = now + 2.0
        anim("oy", keys: [
            TweenKey(target: -0.06, duration: 220, ease: Ease.out),
            TweenKey(target:  0.0,  duration: 220, ease: Ease.back),
        ])

        // 0.25s: hands out + body squash + sound
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.anim("hands", keys: [TweenKey(target: 1, duration: 280, ease: Ease.out)])
            self.anim("sy", keys: [
                TweenKey(target: 0.95, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            self.anim("sx", keys: [
                TweenKey(target: 1.04, duration: 100, ease: Ease.out),
                TweenKey(target: 1.0,  duration: 260, ease: Ease.back),
            ])
            SoundEngine.shared.play("greet")
        }

        // 0.55s: first blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.blink()
        }

        // 1.50s: second blink
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.50) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.blink()
        }

        // 1.55s: retract hands
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.waveUntil = 0
            self.anim("hands", keys: [TweenKey(target: 0, duration: 200, ease: Ease.inOut)])
        }

        // 1.75s: brief happy eyes then back to normal
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) { [weak self] in
            guard let self, self.greetToken == tok else { return }
            self.eyeOverride = .happy
            self.eyeOverrideUntil = CACurrentMediaTime() + 0.30
        }
    }

    /// Immediately interrupts an in-progress greeting (hands retract in 150 ms).
    func interruptGreet() {
        guard hands > 0.01 || CACurrentMediaTime() < waveUntil else { return }
        greetToken += 1   // invalidate any pending closures
        waveUntil = 0
        waveStart = 0
        anim("hands", keys: [TweenKey(target: 0, duration: 150, ease: Ease.inOut)])
    }

    /// Sets a permanent eye expression that survives blinks and transient emotes.
    func setPermanentEmote(_ emote: BotEmote?) {
        permanentEmote = emote
        // .wink fires periodically — don't freeze the eye (normal between winks)
        if emote == .wink {
            miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
            return
        }
        permanentEye = emote.map { emoteEyeShape($0) }
        if let eye = permanentEye {
            eyeOverride = eye
            eyeOverrideUntil = .greatestFiniteMagnitude
        } else {
            if eyeOverrideUntil == .greatestFiniteMagnitude {
                eyeOverride = nil
                eyeOverrideUntil = 0
            }
        }
        // Stagger first periodic behavior so bots don't all fire at once
        miniNextBehavior = CACurrentMediaTime() + Double.random(in: 0.8...2.5)
    }

    func triggerEmote(_ emote: BotEmote, duration: Double = 1.8, silent: Bool = false) {
        let now = CACurrentMediaTime()
        eyeOverride = emoteEyeShape(emote)
        eyeOverrideUntil = now + duration

        switch emote {
        case .love:
            // Grafite: piscadela e um pulinho, sem corações nem rubor
            anim("tilt", keys: [
                TweenKey(target: 0.12, duration: 160, ease: Ease.out),
                TweenKey(target: 0, duration: 300, ease: Ease.inOut),
            ])
            anim("oy", keys: [
                TweenKey(target: -0.1, duration: 160, ease: Ease.out),
                TweenKey(target: 0,    duration: 300, ease: Ease.back),
            ])
        case .surprised:
            anim("oy", keys: [
                TweenKey(target: -0.3, duration: 140, ease: Ease.out),
                TweenKey(target: 0,    duration: 380, ease: Ease.back),
            ])
            anim("es", keys: [
                TweenKey(target: 1.25, duration: 120, ease: Ease.out),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
        case .proud:
            emit(.star, count: 5)
            anim("tilt", keys: [
                TweenKey(target: -0.14, duration: 220, ease: Ease.out),
                TweenKey(target: -0.14, duration: CGFloat((duration - 0.5) * 1000), ease: Ease.lin),
                TweenKey(target: 0,     duration: 280, ease: Ease.inOut),
            ])
            anim("blush", keys: [
                TweenKey(target: 0.7, duration: 250, ease: Ease.out),
                TweenKey(target: 0.7, duration: CGFloat((duration - 0.5) * 1000), ease: Ease.lin),
                TweenKey(target: 0,   duration: 300, ease: Ease.inOut),
            ])
        case .wink:
            anim("tilt", keys: [
                TweenKey(target: 0.12, duration: 160, ease: Ease.out),
                TweenKey(target: 0.12, duration: CGFloat((duration - 0.4) * 1000), ease: Ease.lin),
                TweenKey(target: 0,    duration: 240, ease: Ease.inOut),
            ])
        case .yawn:
            anim("sy", keys: [
                TweenKey(target: 1.12, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
            anim("sx", keys: [
                TweenKey(target: 0.94, duration: 500, ease: Ease.inOut),
                TweenKey(target: 1,    duration: 500, ease: Ease.inOut),
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                self?.eyeOverride = .closed
                self?.emit(.z, count: 2)
            }
        case .happy:
            anim("blush", keys: [
                TweenKey(target: 0.6, duration: 200, ease: Ease.out),
                TweenKey(target: 0,   duration: 600, ease: Ease.inOut),
            ])
        case .annoyed:
            eyeOverride = .line
            eyeOverrideUntil = now + 0.8
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                SoundEngine.shared.play("annoyed")
            }
        }
    }

    func emit(_ type: Particle.ParticleType, count: Int) {
        for i in 0..<count {
            let isZ = type == .z
            let p = Particle(
                type: type,
                x: (CGFloat.random(in: -0.5...0.5)) * 0.9 + (isZ ? 0.55 : 0),
                y: -0.7 - CGFloat.random(in: 0...0.2),
                vx: CGFloat.random(in: -0.5...0.5) * 0.35 + (isZ ? 0.18 : 0),
                vy: -(0.45 + CGFloat.random(in: 0...0.35)),
                age: -Double(i) * 0.14,
                life: 1.3 + Double.random(in: 0...0.5),
                rot: CGFloat.random(in: 0...(.pi * 2)),
                size: 0.15 + CGFloat.random(in: 0...0.08)
            )
            particles.append(p)
        }
    }

    // MARK: - Update (called every frame from TimelineView)

    /// Avança a física no ritmo em que ela foi afinada: um passo de 0,05 a cada 1/60 s de
    /// tempo real (era assim a 60 quadros), qualquer que seja a taxa de quadros de quem desenha.
    private var ultimoAvanco: CFTimeInterval = 0
    func avancar() {
        let agora = CACurrentMediaTime()
        let passos = ultimoAvanco == 0 ? 1 : min(6, max(1, Int(((agora - ultimoAvanco) * 60).rounded())))
        ultimoAvanco = agora
        for _ in 0..<passos { update(dt: 0.05) }
    }

    func update(dt: Double) {
        let now = CACurrentMediaTime()
        let dtCG = CGFloat(dt)
        let comFones = headphonesOn || nivelProp == .fones
        headphonesAmt += ((comFones ? 1 : 0) - headphonesAmt) * min(1, dtCG * 7)
        celularAmt += ((nivelProp == .celular ? 1 : 0) - celularAmt) * min(1, dtCG * 9)
        nivelVis += (nivelValor - nivelVis) * min(1, dtCG * 12)
        atualizarReacaoNivel(dt: dt)

        // Process tweens
        for key in tweens.keys {
            guard var tw = tweens[key] else { continue }
            let k = tw.keys[tw.keyIndex]
            let elapsed = now * 1000 - tw.startTime
            let p = min(1, max(0, CGFloat(elapsed) / k.duration))
            let val = tw.from + (k.target - tw.from) * k.ease(p)
            setProperty(key, value: val)

            if p >= 1 {
                tw.from = k.target
                tw.keyIndex += 1
                tw.startTime = now * 1000
                if tw.keyIndex >= tw.keys.count {
                    tweens.removeValue(forKey: key)
                    locks.remove(key)
                    tw.onComplete?()
                } else {
                    tweens[key] = tw
                }
            } else {
                tweens[key] = tw
            }
        }

        // Compute look targets
        let t = CGFloat(now - t0)
        var ty: CGFloat = lookX * 0.62
        var tp: CGFloat = lookY * 0.5

        if let fixedLook = cfg.look {
            ty = ty * 0.35 + fixedLook.x * 0.55
            tp = tp * 0.3  + fixedLook.y * 0.5
        }
        if cfg.scans {
            ty = sin(t * 2.6) * 0.6
            tp = -0.06
        }
        if state == .sleeping { ty = 0; tp = -0.14 }
        if state == .dizzy    { ty = sin(t * 9) * 0.25 }

        // Mini bots: override look with random wandering (never follows mouse)
        if isMini && cfg.look == nil && !cfg.scans && state != .sleeping && state != .dizzy {
            if now > miniLookNextTime {
                miniLookTarget = CGPoint(
                    x: CGFloat.random(in: -0.88...0.88),
                    y: CGFloat.random(in: -0.55...0.45)
                )
                miniLookNextTime = now + Double.random(in: 0.5...2.0)
            }
            ty = miniLookTarget.x * 0.62
            tp = miniLookTarget.y * 0.5
        }

        tgYaw   = ty
        tgPitch = tp
        tgTilt  = cfg.tilt

        // Body sway during greeting wave
        if now > waveStart && now < waveUntil {
            let wt = CGFloat(now - waveStart)
            tgTilt = -0.06 + sin(2 * .pi * 1.2 * wt) * 0.07
        }

        let bounce = cfg.bounces ? -abs(sin(t * 5.2)) * 0.07 : CGFloat(0)
        // oy tween can override if not locked
        if !locks.contains("oy") { oy += (bounce - oy) * CGFloat(1 - pow(0.0008, dt)) }

        if cfg.breathes {
            let amp: CGFloat = isMini ? 0.07 : 0.035
            tgSy = 1 + sin(t * 1.8) * amp
            tgSx = 1 - sin(t * 1.8) * amp * 0.57
        } else if isMini {
            // Subtle idle pulse (unique phase per engine via t0)
            tgSy = 1 + sin(t * 2.2) * 0.04
            tgSx = 1 - sin(t * 2.2) * 0.02
        } else {
            tgSy = 1; tgSx = 1
        }

        // Mini bots: periodic dramatic behaviors
        if isMini && now > miniNextBehavior {
            doMiniBehaviorLoop()
        }

        // Smooth look
        let kLook = CGFloat(1 - pow(0.0025, dt))
        let kGen  = CGFloat(1 - pow(0.0008, dt))

        if !locks.contains("yaw")   { yaw   += (tgYaw   - yaw)   * kLook }
        if !locks.contains("pitch") { pitch += (tgPitch  - pitch) * kLook }
        if !locks.contains("tilt")  { tilt  += (tgTilt   - tilt)  * kGen  }
        if !locks.contains("sy")    { sy    += (tgSy     - sy)    * kGen  }
        if !locks.contains("sx")    { sx    += (tgSx     - sx)    * kGen  }
        if !locks.contains("es")    { es    += (tgEs     - es)    * kGen  }

        // Animate color
        col = mixColor(col, colT, 1 - pow(0.002, dt))

        // Blink
        if now > nextBlink {
            if state != .sleeping && state != .dizzy {
                blink()
                if Double.random(in: 0...1) < 0.22 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) { [weak self] in self?.blink() }
                }
            }
            nextBlink = now + 2.2 + Double.random(in: 0...3.2)
        }

        // Clear expired eye override (restore permanent if set)
        if eyeOverride != nil && now > eyeOverrideUntil {
            eyeOverride = permanentEye
            if permanentEye != nil { eyeOverrideUntil = .greatestFiniteMagnitude }
        }

        // Ambient particles
        if now - lastAmbient > 1.3 {
            lastAmbient = now
            if cfg.zz { emit(.z, count: 1) }   // ZZZ works for mini too
            if !isMini && cfg.sweat && Double.random(in: 0...1) < 0.5 { emit(.sweat, count: 1) }
        }

        // Age particles
        for i in particles.indices { particles[i].age += dt }
        particles.removeAll { $0.age >= $0.life }

        // Mouth slot spring — ω₀ ≈ 25 rad/s (T=0.25s), ζ=0.6 (underdamped, slight clack)
        let slotOmega: CGFloat = 2 * .pi / 0.25
        let slotZeta: CGFloat = 0.6
        let slotAcc = slotOmega * slotOmega * (slotHTarget - slotH)
                    - 2 * slotZeta * slotOmega * slotHVel
        slotHVel += slotAcc * dtCG
        slotH = max(0, slotH + slotHVel * dtCG)

        lastTime = now
    }

    // MARK: - Draw

    func draw(context: GraphicsContext, size: CGSize) {
        let W = size.width
        let H = size.height
        let R = W * 0.3
        let rx = R * 1.14
        let ry = R * 0.88

        let reacao = reacaoNivel()
        let cx = W / 2 + (ox + reacao.dx) * R
        // particleOverhang shifts the bot body down in canvas coords so hearts can fly into
        // the extended canvas above without clipping (BotPlacement compensates with position offset)
        let cy = H / 2 + particleOverhang / 2 + (oy + reacao.dy) * R + R * 0.06

        var ctx = context
        ctx.translateBy(x: cx, y: cy)
        let giro = tilt + reacao.tilt
        if giro != 0 { ctx.rotate(by: .radians(giro)) }
        ctx.scaleBy(x: sx, y: sy)

        // Body path (superellipse for Homie, morph to rect for upload)
        let bodyPath = botPath(rx: rx, ry: ry, morph: morph, R: R)

        // AirPods atrás da cabeça: desenhados antes do corpo, que esconde a metade de dentro
        if BotStyle.earbuds && headphonesAmt > 0.01 && morph < 0.5 && !isMini {
            drawEarbuds(ctx: &ctx, R: R, rx: rx, ry: ry, amt: headphonesAmt, front: false)
        }

        // Body fill
        drawBody(ctx: &ctx, path: bodyPath, R: R, rx: rx, ry: ry)

        // Blush — always shows a floor proportional to tint (prototype behaviour)
        // Estilo grafite: sem rubor. Contorno preto grosso por cima do corpo.
        drawOutline(ctx: &ctx, path: bodyPath, R: R)

        // Luz da tela do celular no rosto: mais forte quanto mais brilho
        if celularAmt > 0.01 && morph < 0.5 && !isMini {
            var luz = ctx
            luz.clip(to: bodyPath)
            let a = Double(celularAmt * (0.04 + pow(nivelVis, 1.2) * 0.7))
            luz.fill(Path(ellipseIn: CGRect(x: -rx * 1.2, y: -ry * 0.2, width: rx * 2.4, height: ry * 2.0)),
                     with: .radialGradient(Gradient(colors: [Color(red: 0.86, green: 0.93, blue: 1).opacity(a), .clear]),
                                           center: CGPoint(x: 0, y: ry * 0.9), startRadius: 0, endRadius: rx * 1.25))
        }

        // Eyes (em cópia: drawEyes recorta no corpo, e o fone precisa sair dele)
        var eyesCtx = ctx
        drawEyes(ctx: &eyesCtx, path: bodyPath, R: R, rx: rx, ry: ry)

        if celularAmt > 0.01 && morph < 0.5 && !isMini {
            drawCelular(ctx: &ctx, R: R, rx: rx, ry: ry, amt: celularAmt, nivel: nivelVis)
        }

        // AirPod que o giro trouxe para a frente: por cima do corpo
        if BotStyle.earbuds && headphonesAmt > 0.01 && morph < 0.5 && !isMini {
            drawEarbuds(ctx: &ctx, R: R, rx: rx, ry: ry, amt: headphonesAmt, front: true)
        }

        // Fone (música tocando)
        if headphonesAmt > 0.01 && morph < 0.5 {
            if !BotStyle.earbuds {
                drawHeadphones(ctx: &ctx, R: R, rx: rx, ry: ry, amt: headphonesAmt)
            }
        }

        // Boné: sempre assentado, também no formato de caixa
        if BotStyle.cap && !isMini {
            var capCtx = ctx
            drawCap(ctx: &capCtx, R: R,
                    rx: lerp(rx, R * 1.0, morph), ry: lerp(ry, R * 0.94, morph))
        }

        // Reset transform for hands, badge, particles which need world coords
        // (We'll pass world-space cx/cy to these helpers)
    }

    // MARK: - Draw hands behind body (called before draw() so hands appear under Homie)

    func drawHandsBehind(context: GraphicsContext, size: CGSize) {
        guard hands > 0.01, !isMini else { return }
        let W = size.width, H = size.height
        let R = W * 0.3
        // Only draw hands when Homie is large enough to be meaningful (not compact/peek)
        guard R > 14 else { return }
        let rx = R * 1.14
        let ry = R * 0.88
        let cx = W / 2 + ox * R
        let cy = H / 2 + particleOverhang / 2 + oy * R + R * 0.06

        let now = CACurrentMediaTime()
        let bodyH = 2 * ry   // full body height

        // Hand ellipse half-dims: 0.30×bodyH wide, 0.26×bodyH tall (scaled by hands 0→1)
        let hew = 0.30 * ry * hands   // half-width
        let heh = 0.26 * ry * hands   // half-height

        // Body half-dims with current squash scale
        let hwB = rx * sx
        let hhB = ry * sy

        let isWaving = now >= waveStart && waveStart > 0 && now < waveUntil

        for sd in [-1.0, 1.0] {
            var localX: CGFloat
            var localY: CGFloat
            var handRot: CGFloat = 0

            if sd > 0 && isWaving {
                // Right hand: rise to wave position over first 180ms, then oscillate
                let wt = CGFloat(now - waveStart)
                let rise = min(1.0, wt / 0.18)
                let riseEased: CGFloat = 1 - pow(1 - rise, 3)   // easeOut cubic

                // Rest position is lower-side; wave position is upper-side (at eye height)
                let restX: CGFloat = hwB * 1.08
                let restY: CGFloat = hhB * 0.70
                let oscX = cos(13 * wt) * 0.06 * bodyH
                let oscY = -sin(13 * wt) * 0.14 * bodyH
                let waveX: CGFloat = hwB * 1.10 + oscX
                let waveY: CGFloat = -hhB * 0.15 + oscY
                localX = restX + (waveX - restX) * riseEased
                localY = restY + (waveY - restY) * riseEased
                handRot = (-0.5 + sin(13 * wt) * 0.35) * riseEased

            } else if sd < 0 && isWaving {
                // Left hand: gentle sway at rest position
                let wt = CGFloat(now - waveStart)
                localX = -hwB * 1.08
                localY = hhB * 0.70 + sin(6 * wt) * 0.04 * bodyH

            } else {
                // Rest: lower-side, clearly peeking behind body bottom
                localX = CGFloat(sd) * hwB * 1.08
                localY = hhB * 0.70
            }

            // Apply body tilt to get world position
            let cosT = cos(tilt), sinT = sin(tilt)
            let worldX = cx + cosT * localX - sinT * localY
            let worldY = cy + sinT * localX + cosT * localY

            // Draw
            var handCtx = context
            handCtx.translateBy(x: worldX, y: worldY)
            if handRot != 0 { handCtx.rotate(by: .radians(handRot)) }

            let handRect = CGRect(x: -hew, y: -heh, width: hew * 2, height: heh * 2)
            var handPath = Path()
            handPath.addEllipse(in: handRect)

            // Mesmo material do corpo (cor inteira do estado)
            HomieCorpo.pintarMao(ctx: &handCtx, path: handPath, meiaAltura: heh, tons: tonsDoCorpoAgora())

            // Subtle separation border — rgba(0,0,0,0.08) 1pt
            handCtx.stroke(handPath, with: .color(Color.black.opacity(0.08)), lineWidth: 1)
        }
    }

    func drawHandsAndExtras(context: GraphicsContext, size: CGSize) {
        let W = size.width
        let H = size.height
        let R = W * 0.3
        let rx = R * 1.14
        let ry = R * 0.88
        let cx = W / 2 + ox * R
        let cy = H / 2 + particleOverhang / 2 + oy * R + R * 0.06

        // Badge — hidden while morphing to mailbox
        if let badge = badge, badgeS > 0.01, morph < 0.25 {
            drawBadge(context: context, size: size, badge: badge, R: R, rx: rx, ry: ry, cx: cx, cy: cy)
        }

        // Particles
        drawParticles(context: context, size: size, R: R, cx: cx, cy: cy)
    }

    // MARK: - Private draw helpers

    func botPath(rx: CGFloat, ry: CGFloat, morph: CGFloat, R: CGFloat) -> Path {
        let n = 72
        let expN: CGFloat = 2.0 / 2.7
        // Target mailbox dims (spec: 1.0R wide, 0.94R tall, 0.42R corner radius)
        let tw = R * 1.0
        let th = R * 0.94
        let tr = R * 0.42
        var path = Path()
        for i in 0...n {
            let a = CGFloat(i) / CGFloat(n) * .pi * 2
            let ca = cos(a), sa = sin(a)
            let px0 = rx * (ca >= 0 ? pow(ca, expN) : -pow(-ca, expN))
            let py0 = ry * (sa >= 0 ? pow(sa, expN) : -pow(-sa, expN))
            let px: CGFloat
            let py: CGFloat
            if morph < 0.005 {
                px = px0; py = py0
            } else {
                let rr = rrPoint(ca: ca, sa: sa, W: tw, H: th, cr: tr)
                px = lerp(px0, rr.x, morph)
                py = lerp(py0, rr.y, morph)
            }
            if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
            else { path.addLine(to: CGPoint(x: px, y: py)) }
        }
        path.closeSubpath()
        return path
    }

    /// Ray-rounded-rect intersection: find the point on the rounded rect boundary in direction (ca, sa).
    private func rrPoint(ca: CGFloat, sa: CGFloat, W: CGFloat, H: CGFloat, cr: CGFloat) -> CGPoint {
        let eps: CGFloat = 1e-6
        let kx: CGFloat = ca >= 0 ? 1 : -1
        let ky: CGFloat = sa >= 0 ? 1 : -1
        let cx = kx * (W - cr)
        let cy = ky * (H - cr)

        // Try corner arc
        let dot  = ca * cx + sa * cy
        let disc = dot * dot - (cx*cx + cy*cy - cr*cr)
        if disc >= 0 {
            let t = dot + sqrt(disc)
            if t > eps {
                let px = ca * t, py = sa * t
                if abs(px) >= W - cr - eps && abs(py) >= H - cr - eps {
                    return CGPoint(x: px, y: py)
                }
            }
        }

        // Horizontal edge |y| = H
        if abs(sa) > eps {
            let t = (ky * H) / sa
            if t > eps {
                let x = ca * t
                if abs(x) <= W - cr + eps { return CGPoint(x: x, y: ky * H) }
            }
        }
        // Vertical edge |x| = W
        if abs(ca) > eps {
            let t = (kx * W) / ca
            if t > eps {
                let y = sa * t
                if abs(y) <= H - cr + eps { return CGPoint(x: kx * W, y: y) }
            }
        }

        return CGPoint(x: kx * W, y: ky * H)
    }

    private func drawBody(ctx: inout GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        let tons = tonsDoCorpoAgora()
        if isMini {
            HomieCorpo.pintarMini(ctx: &ctx, path: path, ry: ry, tons: tons)
        } else {
            HomieCorpo.pintar(ctx: &ctx, path: path, R: R, rx: rx, ry: ry, tons: tons,
                              sombraDoBone: BotStyle.cap && morph < 0.5)
        }
    }

    /// AirPods no traço do Homie, presos às laterais de uma cabeça que gira (yaw):
    /// orelha a ±90° na esfera; o fone se projeta com x, profundidade e escorço.
    /// `front` = desenhar só o que veio para a frente (vai por cima do corpo);
    /// o resto é desenhado antes do corpo e fica meio escondido atrás da cabeça.
    private func drawEarbuds(ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat, amt: CGFloat, front: Bool) {
        let pop = amt < 1 ? 0.6 + 0.4 * amt + 0.12 * sin(amt * .pi) : 1
        let top = colorFromTuple(cgColorToTuple(BotConst.baseTop))
        let bottom = colorFromTuple(cgColorToTuple(BotConst.baseBottom))
        for side in [-1.0, 1.0] as [CGFloat] {
            let a = side * .pi / 2 + yaw
            let depth = cos(a)                         // > 0: virou para a frente
            if front != (depth > 0.08) { continue }
            let sx = sin(a)                            // posição lateral (−1…1)
            let ex = sx * (rx * 0.97 + R * 0.06)
            let ey = ry * 0.02 - sin(pitch) * ry * 0.3
            // escorço: de perfil (na borda) a peça aparece inteira; de frente, mais estreita
            let squash = 0.72 + 0.28 * abs(sx)
            var c = ctx
            c.opacity = Double(min(1, amt * 1.5))
            c.translateBy(x: ex, y: ey)
            c.scaleBy(x: pop * squash, y: pop)
            let out: CGFloat = sx >= 0 ? 1 : -1        // lado de fora na tela
            c.rotate(by: .radians(Double(out) * 0.20 * abs(sx)))

            var bud = Path(ellipseIn: CGRect(x: -R * 0.17, y: -R * 0.16, width: R * 0.34, height: R * 0.32))
            bud.addPath(Path(roundedRect: CGRect(x: out * R * 0.05 * abs(sx) - R * 0.065, y: 0, width: R * 0.13, height: R * 0.40),
                             cornerRadius: R * 0.065))
            if front {
                // sombra de contato no rosto, para não virar mancha branca sobre branco
                c.fill(bud.offsetBy(dx: -out * R * 0.04, dy: R * 0.03), with: .color(Color.black.opacity(0.18)))
            }
            c.fill(bud, with: .linearGradient(Gradient(colors: [top, bottom]),
                                              startPoint: CGPoint(x: out * R * 0.10, y: -R * 0.16),
                                              endPoint: CGPoint(x: -out * R * 0.05, y: R * 0.40)))
            if front {
                c.stroke(bud, with: .color(Color.black.opacity(0.12)), lineWidth: R * 0.012)
            }
            c.fill(Path(ellipseIn: CGRect(x: out * R * 0.07 - R * 0.07, y: -R * 0.12, width: R * 0.14, height: R * 0.09)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9), .clear]),
                                         center: CGPoint(x: out * R * 0.07, y: -R * 0.075), startRadius: 0, endRadius: R * 0.08))
        }
    }

    /// AirPods Max: canopy de malha colado no topo (segue o boné), hastes de aço finas e
    /// conchas de alumínio apertadas contra a cabeça, com coroa digital na direita.
    private func drawHeadphones(ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat, amt: CGFloat) {
        var c = ctx
        c.opacity = Double(min(1, amt * 1.4))
        let dy = -(1 - amt) * R * 0.6
        let silver = BotStyle.phonesSilver
        let alu0 = silver ? Color(red: 0.93, green: 0.93, blue: 0.94) : Color(red: 0.42, green: 0.43, blue: 0.46)
        let alu1 = silver ? Color(red: 0.70, green: 0.71, blue: 0.73) : Color(red: 0.20, green: 0.21, blue: 0.23)
        let mesh = silver ? Color(red: 0.86, green: 0.86, blue: 0.87) : Color(red: 0.30, green: 0.31, blue: 0.33)
        let steel = Color(red: 0.80, green: 0.82, blue: 0.85)

        // Topo que o canopy acompanha: o boné ou a própria cabeça
        let half = BotStyle.cap ? rx * 1.02 : rx * 0.98
        let topY = (BotStyle.cap ? -ry * 1.22 : -ry * 0.98) - R * 0.05 + dy
        let endY = (BotStyle.cap ? -ry * 0.58 : -ry * 0.40) + dy
        func arc(_ inset: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: -half - inset, y: endY))
            p.addCurve(to: CGPoint(x: 0, y: topY - inset),
                       control1: CGPoint(x: -half - inset, y: topY + (endY - topY) * 0.25 - inset),
                       control2: CGPoint(x: -rx * 0.62, y: topY - inset))
            p.addCurve(to: CGPoint(x: half + inset, y: endY),
                       control1: CGPoint(x: rx * 0.62, y: topY - inset),
                       control2: CGPoint(x: half + inset, y: topY + (endY - topY) * 0.25 - inset))
            return p
        }

        // Conchas: centro um pouco para dentro da borda (apertadas na cabeça)
        let w = R * 0.40, h = R * 0.74
        let cupCY = ry * 0.04 + dy
        let cupX = rx * 1.00

        // Hastes de aço: saem do canopy e entram no topo das conchas
        for side in [-1.0, 1.0] as [CGFloat] {
            var stem = Path()
            stem.move(to: CGPoint(x: side * (half + R * 0.02), y: endY - R * 0.04))
            stem.addQuadCurve(to: CGPoint(x: side * cupX, y: cupCY - h / 2 + R * 0.04),
                              control: CGPoint(x: side * (half + R * 0.10), y: (endY + cupCY - h / 2) / 2))
            c.stroke(stem, with: .color(steel), style: StrokeStyle(lineWidth: R * 0.045, lineCap: .round))
            c.stroke(stem, with: .color(Color.white.opacity(0.5)), style: StrokeStyle(lineWidth: R * 0.015, lineCap: .round))
        }

        // Canopy de malha (faixa larga colada no topo) + textura
        c.stroke(arc(R * 0.02), with: .color(mesh), style: StrokeStyle(lineWidth: R * 0.14, lineCap: .round))
        c.stroke(arc(R * 0.02), with: .color(Color.black.opacity(0.18)),
                 style: StrokeStyle(lineWidth: R * 0.14, lineCap: .round, dash: [R * 0.018, R * 0.03]))
        c.stroke(arc(-R * 0.03), with: .color(Color.white.opacity(0.18)), style: StrokeStyle(lineWidth: R * 0.02, lineCap: .round))

        for side in [-1.0, 1.0] as [CGFloat] {
            let rect = CGRect(x: side * cupX - w / 2, y: cupCY - h / 2, width: w, height: h)
            let cup = Path(roundedRect: rect, cornerRadius: R * 0.17)
            // sombra de contato na cabeça
            c.fill(Path(roundedRect: rect.offsetBy(dx: -side * R * 0.03, dy: R * 0.03), cornerRadius: R * 0.17),
                   with: .color(Color.black.opacity(0.18)))
            // alumínio
            c.fill(cup, with: .linearGradient(Gradient(colors: [alu0, alu1]),
                                              startPoint: CGPoint(x: rect.minX, y: rect.minY),
                                              endPoint: CGPoint(x: rect.maxX, y: rect.maxY)))
            // aro da almofada (lado da cabeça)
            let cushion = CGRect(x: side < 0 ? rect.maxX - w * 0.26 : rect.minX, y: rect.minY + R * 0.03,
                                 width: w * 0.26, height: h - R * 0.06)
            c.fill(Path(roundedRect: cushion, cornerRadius: R * 0.10),
                   with: .color(silver ? Color(red: 0.80, green: 0.80, blue: 0.82) : Color(red: 0.14, green: 0.15, blue: 0.16)))
            // reflexo do alumínio
            c.fill(Path(roundedRect: CGRect(x: rect.minX + w * (side < 0 ? 0.14 : 0.40), y: rect.minY + h * 0.08,
                                            width: w * 0.30, height: h * 0.42), cornerRadius: R * 0.06),
                   with: .color(Color.white.opacity(silver ? 0.55 : 0.20)))
            c.stroke(cup, with: .color(Color.black.opacity(0.35)), lineWidth: R * 0.02)
        }
        // Coroa digital em cima da concha direita
        let crown = CGRect(x: cupX + w * 0.05, y: cupCY - h / 2 - R * 0.07, width: R * 0.10, height: R * 0.09)
        c.fill(Path(roundedRect: crown, cornerRadius: R * 0.025), with: .color(alu1))
        c.stroke(Path(roundedRect: crown, cornerRadius: R * 0.025), with: .color(Color.black.opacity(0.3)), lineWidth: R * 0.012)
    }

    /// Contorno preto grosso (grafite). Nos Homies pequenos, mais fino.
    private func drawOutline(ctx: inout GraphicsContext, path: Path, R: CGFloat) {
        guard morph < 0.5, BotStyle.outline || isMini else { return }
        let w = isMini ? R * 0.10 : R * 0.05
        ctx.stroke(path, with: .color(Color(red: 0.04, green: 0.04, blue: 0.05)),
                   style: StrokeStyle(lineWidth: w, lineJoin: .round))
    }

    /// Sobrancelha grossa acima de um olho; inclinação e altura mudam com o estado.
    /// `sd` −1 = olho esquerdo, +1 = direito. Ponta interna desce quando bravo.
    private func drawBrow(ctx: inout GraphicsContext, w: CGFloat, h: CGFloat, sd: CGFloat, R: CGFloat, shape: EyeShape) {
        var slope: CGFloat = 0.10     // >0: ponta de dentro mais baixa (sério/bravo)
        var raise: CGFloat = 0        // >0: sobe
        switch state {
        case .working, .searching:  slope = 0.28
        case .error, .ratelimit:    slope = 0.55; raise = -0.02
        case .approval, .question:  slope = -0.18; raise = 0.10
        case .thinking:             slope = sd < 0 ? -0.25 : 0.20; raise = sd < 0 ? 0.08 : 0
        case .finished:             slope = 0.0; raise = 0.03
        case .sleeping:             slope = -0.05; raise = -0.04
        default: break
        }
        if shape == .line { slope = 0.6 }            // emote bravo
        if shape == .dot  { slope = -0.25; raise = 0.14 }  // surpreso
        let L = w * 1.55
        raise *= 0.5                                  // sobe pouco, para não sumir debaixo do boné
        let base = -h * 0.92 - R * 0.07 - raise * R
        let inner = -sd                               // lado de dentro em x
        var brow = Path()
        brow.move(to: CGPoint(x: -L / 2, y: base + slope * (-L / 2) * inner))
        brow.addLine(to: CGPoint(x: L / 2, y: base + slope * (L / 2) * inner))
        ctx.stroke(brow, with: .color(Color(cgColor: BotConst.ink)),
                   style: StrokeStyle(lineWidth: R * 0.075 * Detalhe(R: R).sobrancelha, lineCap: .round))
    }

    private func drawBlush(ctx: inout GraphicsContext, path: Path, rx: CGFloat, ry: CGFloat, R: CGFloat, blush: CGFloat) {
        ctx.clip(to: path)
        let yOffset = sin(yaw) * rx * 0.8
        for sd in [-1.0, 1.0] {
            let bx = CGFloat(sd) * rx * 0.55 + yOffset
            let by = ry * 0.2
            var ellipse = Path()
            ellipse.addEllipse(in: CGRect(x: bx - R*0.17, y: by - R*0.1, width: R*0.34, height: R*0.2))
            ctx.fill(ellipse, with: .color(Color(red: 1, green: 0.471, blue: 0.588, opacity: Double(0.5 * blush))))
        }
    }

    /// Reação ao nível: pulo a cada mudança, olhos maiores ou menores, notas saindo dos fones.
    private func atualizarReacaoNivel(dt: Double) {
        let dtCG = CGFloat(dt)
        guard nivelProp != .nenhum, !isMini else {
            nivelAnterior = -1
            nivelPulo = 0
            nivelEs += (1 - nivelEs) * min(1, dtCG * 8)
            return
        }
        if nivelAnterior >= 0 && abs(nivelValor - nivelAnterior) > 0.001 {
            nivelPulo = nivelValor > nivelAnterior ? 1 : -1
        }
        nivelAnterior = nivelValor
        nivelPulo *= max(0, 1 - dtCG * 5)

        let v = nivelVis
        var alvoEs: CGFloat = 1
        switch nivelProp {
        case .fones:
            if nivelValor <= 0.001 { alvoEs = 0.9 }
            else if v < 0.2 { alvoEs = 1.3 }          // arregala tentando ouvir
            else if v > 0.88 { alvoEs = 1.15 }
            // Notas saindo dos fones: mais e mais rápidas quanto mais alto
            if nivelValor > 0.05 {
                notaAcumulada += dt * Double(0.6 + v * 5)
                while notaAcumulada >= 1 {
                    notaAcumulada -= 1
                    let lado: CGFloat = Bool.random() ? 1 : -1
                    particles.append(Particle(type: .nota,
                        x: lado * (0.62 + CGFloat.random(in: 0...0.15)), y: -0.05,
                        vx: lado * (0.25 + v * 0.45), vy: -(0.35 + v * 0.55),
                        age: 0, life: 0.9 + Double(v) * 0.4,
                        rot: CGFloat.random(in: -0.4...0.4), size: 0.13 + v * 0.10))
                }
                if v > 0.9, Int.random(in: 0..<40) == 0 { emit(.sweat, count: 1) }
            } else if Int.random(in: 0..<90) == 0 {
                emit(.z, count: 1)                    // mudo: cochila
            }
        case .celular:
            if v < 0.15 { alvoEs = 1.28 }             // escuro: olho bem aberto
            if v > 0.95, Int.random(in: 0..<25) == 0 { emit(.spark, count: 1) }
        case .nenhum:
            break
        }
        nivelEs += (alvoEs + nivelPulo * 0.12 - nivelEs) * min(1, dtCG * 10)
    }

    private func olhoNivel() -> EyeShape? {
        let v = nivelVis
        switch nivelProp {
        case .nenhum: return nil
        case .fones:
            if nivelValor <= 0.001 { return .closed }   // mudo: cochila
            if v < 0.2 { return .wide }                  // baixinho: se esforça para ouvir
            if v > 0.88 { return .aperto }               // alto demais: "> <"
            if v > 0.6 { return .curtindo }              // curtindo o som: "^ ^"
            return nil
        case .celular:
            if v < 0.15 { return .wide }                 // tela apagada: olho arregalado
            if v > 0.85 { return .aperto }               // ofuscado: "> <"
            return nil
        }
    }

    private func reacaoNivel() -> (dx: CGFloat, dy: CGFloat, tilt: CGFloat) {
        guard nivelProp != .nenhum, !isMini else { return (0, 0, 0) }
        let t = CGFloat(CACurrentMediaTime())
        let v = nivelVis
        let pulo = -nivelPulo * 0.10                       // subiu: pula; desceu: afunda
        switch nivelProp {
        case .fones:
            if nivelValor <= 0.001 { return (0, 0.05, 0.14) }                          // mudo: cabeça caída
            if v > 0.88 { return (sin(t * 46) * 0.04, pulo, sin(t * 31) * 0.05) }      // tremendo
            if v < 0.2 { return (0.04, pulo, 0.2) }                                     // inclina para ouvir
            let ritmo = 3 + v * 6
            return (0, -abs(sin(t * ritmo)) * 0.09 * v + pulo, sin(t * ritmo / 2) * 0.09 * v)  // balança no ritmo
        case .celular:
            // Olha para a tela; ofuscado, recua
            return (0, (v > 0.85 ? -0.05 : 0.02) + pulo, v > 0.85 ? -0.06 : 0)
        case .nenhum:
            return (0, 0, 0)
        }
    }

    /// Celular segurado na frente do corpo; a tela acende com o brilho, junto com a do Mac.
    private func drawCelular(ctx: inout GraphicsContext, R: CGFloat, rx: CGFloat, ry: CGFloat, amt: CGFloat, nivel: CGFloat) {
        var c = ctx
        c.opacity = Double(min(1, amt * 1.3))
        // Embaixo do queixo, sem cobrir os olhos
        let w = R * 0.56, h = R * 0.90
        c.translateBy(x: R * 0.04, y: ry * 1.04 + (1 - amt) * R * 0.9)
        c.rotate(by: .radians(-0.10))
        let corpo = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        let k = Double(nivel)
        let luz = Color(red: 0.90, green: 0.95, blue: 1)
        // Halo: cresce e fica mais forte com o brilho
        if k > 0.02 {
            let raio = h * (0.55 + 1.1 * nivel)
            c.fill(Path(ellipseIn: CGRect(x: -raio, y: -raio, width: raio * 2, height: raio * 2)),
                   with: .radialGradient(Gradient(colors: [luz.opacity(0.15 + 0.55 * k), luz.opacity(0)]),
                                         center: .zero, startRadius: 0, endRadius: raio))
        }
        // Raios de luz quando está bem forte
        if k > 0.55 {
            let forca = (k - 0.55) / 0.45
            for i in 0..<8 {
                let ang = CGFloat(i) / 8 * .pi * 2 + 0.2
                var raio = Path()
                raio.move(to: CGPoint(x: cos(ang) * h * 0.62, y: sin(ang) * h * 0.62))
                raio.addLine(to: CGPoint(x: cos(ang) * h * (0.62 + 0.35 * CGFloat(forca)), y: sin(ang) * h * (0.62 + 0.35 * CGFloat(forca))))
                c.stroke(raio, with: .color(luz.opacity(0.75 * forca)), style: StrokeStyle(lineWidth: R * 0.04, lineCap: .round))
            }
        }
        c.fill(Path(roundedRect: corpo, cornerRadius: R * 0.12), with: .color(Color(red: 0.10, green: 0.11, blue: 0.12)))
        c.stroke(Path(roundedRect: corpo, cornerRadius: R * 0.12), with: .color(Color(cgColor: BotConst.ink)), lineWidth: R * 0.035)
        // Tela: quase preta no mínimo, branca no máximo (curva para a diferença aparecer)
        let tela = corpo.insetBy(dx: R * 0.05, dy: R * 0.05)
        let kk = pow(k, 0.8)
        c.fill(Path(roundedRect: tela, cornerRadius: R * 0.08),
               with: .color(Color(red: 0.05 + 0.93 * kk, green: 0.06 + 0.93 * kk, blue: 0.08 + 0.92 * kk)))
        // "Conteúdo" da tela: linhas que somem quando está escuro
        for (i, larg) in [0.62, 0.44, 0.54].enumerated() {
            let y = tela.minY + tela.height * (0.36 + CGFloat(i) * 0.16)
            c.fill(Path(roundedRect: CGRect(x: tela.minX + tela.width * 0.16, y: y, width: tela.width * larg, height: R * 0.035),
                        cornerRadius: R * 0.018),
                   with: .color(Color(red: 0.35, green: 0.45, blue: 0.62).opacity(0.15 + 0.6 * k)))
        }
        // ilha dinâmica do celular
        c.fill(Path(roundedRect: CGRect(x: -w * 0.16, y: tela.minY + R * 0.04, width: w * 0.32, height: R * 0.06),
                    cornerRadius: R * 0.03), with: .color(Color.black.opacity(0.85)))
        // dedões segurando
        for sd in [-1.0, 1.0] as [CGFloat] {
            let d = CGRect(x: sd * w / 2 - R * 0.09, y: h * 0.08, width: R * 0.18, height: R * 0.24)
            c.fill(Path(ellipseIn: d), with: .color(colorFromTuple(col)))
            c.stroke(Path(ellipseIn: d), with: .color(Color(cgColor: BotConst.ink)), lineWidth: R * 0.03)
        }
    }

    private func drawEyes(ctx: inout GraphicsContext, path: Path, R: CGFloat, rx: CGFloat, ry: CGFloat) {
        var shape = eyeOverride ?? olhoNivel() ?? cfg.eye
        if !isMini && eyeOverride == nil && state == .error { shape = .x }
        // In box mode: cup eyes when file over box (slotHTarget set), happy arcs while chewing
        // Formato caixa (aba de arquivos): mesma cara de sempre — sem caretas
        ctx.clip(to: path)

        for sd in [-1.0, 1.0] {
            let eyeYaw   = CGFloat(sd) * BotConst.eyeSp + yaw
            var eyePitch = BotConst.eyeP + pitch + roll
            // Wrap pitch for roll-through effect
            eyePitch = ((eyePitch + .pi).truncatingRemainder(dividingBy: .pi*2) + .pi*2).truncatingRemainder(dividingBy: .pi*2) - .pi

            let cp = cos(eyePitch)
            guard cos(eyeYaw) * cp > 0.04 else { continue }  // behind head

            let ex = sin(eyeYaw) * cp * rx
            let ey = -sin(eyePitch) * ry + (morph > 0 ? ry * 0.14 * morph : 0)

            let fx = lerp(max(0.18, cos(eyeYaw)), 1, morph * 0.7)
            let fy = lerp(max(0.18, cp),          1, morph * 0.7)

            let eyeMult: CGFloat = isMini ? 1.9 : Detalhe(R: R).olho   // olho maior no desenho pequeno
            let ew = R * BotConst.eyeW * es * nivelEs * eyeMult
            let eh = R * BotConst.eyeH * es * nivelEs * eyeMult

            var eyeCtx = ctx
            eyeCtx.translateBy(x: ex, y: ey)
            eyeCtx.scaleBy(x: fx, y: fy)
            drawEyeShape(ctx: &eyeCtx, shape: shape, w: ew, h: eh, open: open, sd: CGFloat(sd), R: R)
            // no tamanho micro a sobrancelha é só ruído; sai
            if !isMini && morph < 0.3 && BotStyle.brows && shape != .x && Detalhe(R: R) != .micro {
                drawBrow(ctx: &eyeCtx, w: ew, h: eh, sd: CGFloat(sd), R: R, shape: shape)
            }
        }
    }

    private func drawEyeShape(ctx: inout GraphicsContext, shape: EyeShape, w: CGFloat, h: CGFloat, open: CGFloat, sd: CGFloat, R: CGFloat) {
        let ink = isMini ? Color(cgColor: BotConst.miniInk) : Color(cgColor: BotConst.ink)
        let now = CGFloat(CACurrentMediaTime())

        switch shape {
        case .wide:
            drawEyeShape(ctx: &ctx, shape: .pill, w: w*1.16, h: h*1.12, open: open, sd: sd, R: R)

        case .pill where !isMini:
            // Pílula inclinada, alta (tipo Grok)
            ctx.rotate(by: .radians(0.42))
            let pw = w * 0.92
            let hh = max(h * 1.45 * open, pw * 0.3)
            ctx.fill(Path(roundedRect: CGRect(x: -pw/2, y: -hh/2, width: pw, height: hh), cornerRadius: min(pw, hh) / 2),
                     with: .color(ink))

        case .x:
            var p = Path()
            let k = w * 0.62
            p.move(to: CGPoint(x: -k, y: -k)); p.addLine(to: CGPoint(x: k, y: k))
            p.move(to: CGPoint(x: k, y: -k));  p.addLine(to: CGPoint(x: -k, y: k))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.36, lineCap: .round))

        case .pill:
            let hh = max(h * open, w * 0.3)
            var p = Path()
            p.addRoundedRect(in: CGRect(x: -w/2, y: -hh/2, width: w, height: hh),
                             cornerSize: CGSize(width: min(w/2, hh/2), height: min(w/2, hh/2)))
            ctx.fill(p, with: .color(ink))

        case .dot:
            var p = Path()
            p.addEllipse(in: CGRect(x: -w*0.45, y: -w*0.45, width: w*0.9, height: w*0.9))
            ctx.fill(p, with: .color(ink))

        case .line:
            ctx.rotate(by: .radians(-sd * 0.2))
            var p = Path()
            p.addRoundedRect(in: CGRect(x: -w*0.78, y: -w*0.21, width: w*1.56, height: w*0.42),
                             cornerSize: CGSize(width: w*0.21, height: w*0.21))
            ctx.fill(p, with: .color(ink))

        case .aperto:
            // "> <": o da esquerda aponta para dentro (>), o da direita também (<)
            var p = Path()
            let k = w * 0.62
            p.move(to: CGPoint(x: sd * k * 0.8, y: -k))
            p.addLine(to: CGPoint(x: -sd * k * 0.8, y: 0))
            p.addLine(to: CGPoint(x: sd * k * 0.8, y: k))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w * 0.34, lineCap: .round, lineJoin: .round))

        case .flat:
            var p = Path()
            p.addRoundedRect(in: CGRect(x: -w*0.72, y: -w*0.2, width: w*1.44, height: w*0.4),
                             cornerSize: CGSize(width: w*0.2, height: w*0.2))
            ctx.fill(p, with: .color(ink))

        case .happy:
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: h*0.18), radius: w*0.82,
                     startAngle: .degrees(180 + 12), endAngle: .degrees(180 - 12), clockwise: true)
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w*0.5, lineCap: .round))

        case .curtindo:
            // Arco para cima, do tamanho do olho fechado (o .happy é curto demais nesse estilo)
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: h*0.22), radius: w*0.8,
                     startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w*0.38, lineCap: .round))

        case .closed:
            var p = Path()
            p.addArc(center: CGPoint(x: 0, y: -h*0.08), radius: w*0.78,
                     startAngle: .degrees(15), endAngle: .degrees(165), clockwise: false)
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w*0.36, lineCap: .round))

        case .spiral:
            var p = Path()
            var a: CGFloat = 0
            while a < 4.4 * .pi {
                let r  = w * 0.06 + a * w * 0.058
                let aa = a + now * 9 * sd
                let px = cos(aa) * r
                let py = sin(aa) * r
                if a == 0 { p.move(to: CGPoint(x: px, y: py)) }
                else { p.addLine(to: CGPoint(x: px, y: py)) }
                a += 0.2
            }
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w*0.22, lineCap: .round))

        case .heart:
            let heartPath = heartShape(size: w * 1.2)
            ctx.fill(heartPath, with: .color(Color(hex: "#FF4D6D")))

        case .star:
            ctx.rotate(by: .radians(now * 1.5 * sd))
            let starPath = starShape(outer: w * 1.05, inner: w * 0.46)
            ctx.fill(starPath, with: .color(Color(hex: "#F7B32B")))

        case .tired:
            var p1 = Path()
            p1.addRoundedRect(in: CGRect(x: -w/2, y: -h*0.02, width: w, height: h*0.38),
                              cornerSize: CGSize(width: w/2, height: w/2))
            ctx.fill(p1, with: .color(ink))
            var p2 = Path()
            p2.addRoundedRect(in: CGRect(x: -w*0.62, y: -h*0.1, width: w*1.24, height: w*0.22),
                              cornerSize: CGSize(width: w*0.11, height: w*0.11))
            ctx.fill(p2, with: .color(ink))

        case .wink:
            if sd < 0 {
                let hh = max(h * open, w * 0.3)
                var p = Path()
                p.addRoundedRect(in: CGRect(x: -w/2, y: -hh/2, width: w, height: hh),
                                 cornerSize: CGSize(width: min(w/2,hh/2), height: min(w/2,hh/2)))
                ctx.fill(p, with: .color(ink))
            } else {
                var p = Path()
                p.addArc(center: CGPoint(x: 0, y: h*0.18), radius: w*0.82,
                         startAngle: .degrees(180+12), endAngle: .degrees(180-12), clockwise: true)
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: w*0.5, lineCap: .round))
            }

        case .cup:
            // Flat top, rounded bottom corners (like a cup / U-shape)
            let hh = max(h * open, w * 0.3)
            let cr = min(w / 2, hh / 2)  // bottom corner radius
            var p = Path()
            p.move(to: CGPoint(x: -w/2, y: -hh/2))
            p.addLine(to: CGPoint(x: w/2, y: -hh/2))
            p.addLine(to: CGPoint(x: w/2, y: hh/2 - cr))
            p.addQuadCurve(to: CGPoint(x: w/2 - cr, y: hh/2),
                           control: CGPoint(x: w/2, y: hh/2))
            p.addLine(to: CGPoint(x: -w/2 + cr, y: hh/2))
            p.addQuadCurve(to: CGPoint(x: -w/2, y: hh/2 - cr),
                           control: CGPoint(x: -w/2, y: hh/2))
            p.closeSubpath()
            ctx.fill(p, with: .color(ink))
        }
    }

    private func drawBadge(context: GraphicsContext, size: CGSize, badge: BadgeType, R: CGFloat, rx: CGFloat, ry: CGFloat, cx: CGFloat, cy: CGFloat) {
        let bs = badgeS * (isMini ? 1.25 : 1)
        // Selo no ombro direito do boné (como selo de aviso em ícone); à esquerda ficava em cima
        // do encontro da aba com a copa. Os mini-Homies não têm boné: continua no canto esquerdo.
        let bx = isMini ? cx - R * 0.72 * sx : cx + R * 0.84 * sx
        let by = isMini ? cy - R * 0.72 * sy : cy - R * 0.80 * sy
        var ctx = context
        ctx.translateBy(x: bx, y: by)
        ctx.scaleBy(x: bs, y: bs)
        let now = CGFloat(CACurrentMediaTime())

        switch badge {
        case .dots(let col):
            if isMini {
                // Mini: animated pulsing dot
                let phase = (now * 2.4).truncatingRemainder(dividingBy: 1)
                let dotR = R * 0.22 * (1 + 0.25 * sin(phase * .pi * 2))
                var outer = Path()
                outer.addEllipse(in: CGRect(x: -R*0.2, y: -R*0.2, width: R*0.4, height: R*0.4))
                ctx.fill(outer, with: .color(.black))
                var dot = Path()
                dot.addEllipse(in: CGRect(x: -dotR, y: -dotR, width: dotR*2, height: dotR*2))
                ctx.fill(dot, with: .color(Color(cgColor: col)))
            } else {
                // Pill badge with animated dots (prototype style)
                let pw: CGFloat = R * 0.72
                let ph: CGFloat = R * 0.36
                var pill = Path()
                pill.addRoundedRect(in: CGRect(x: -pw/2, y: -ph/2, width: pw, height: ph),
                                    cornerSize: CGSize(width: ph/2, height: ph/2))
                ctx.fill(pill, with: .color(Color(cgColor: col)))
                for i in 0..<3 {
                    let phase = ((now * 2.4 - CGFloat(i) * 0.22).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                    let dotR = R * 0.055 * (1 + 0.4 * max(0, sin(phase * .pi * 2)))
                    var dot = Path()
                    dot.addEllipse(in: CGRect(x: (CGFloat(i)-1)*R*0.18 - dotR, y: -dotR, width: dotR*2, height: dotR*2))
                    ctx.fill(dot, with: .color(.white))
                }
            }

        case .bang(let col), .question(let col):
            var ring = Path()
            ring.addEllipse(in: CGRect(x: -R*0.3, y: -R*0.3, width: R*0.6, height: R*0.6))
            ctx.fill(ring, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R*0.23, y: -R*0.23, width: R*0.46, height: R*0.46))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
            if !isMini {
                // Contorno do caractere guardado uma vez: desenhar Text no Canvas refaz o layout
                // de texto a cada quadro (era o maior custo com aprovação pendente).
                let glifo = badge == .bang(col) ? Glifo.exclamacao : Glifo.interrogacao
                let k = R * 0.32
                ctx.fill(glifo.applying(CGAffineTransform(scaleX: k, y: k)
                                            .concatenating(CGAffineTransform(translationX: 0, y: R*0.02))),
                         with: .color(.white))
            }

        case .dot(let col):
            var outer = Path()
            outer.addEllipse(in: CGRect(x: -R*0.2, y: -R*0.2, width: R*0.4, height: R*0.4))
            ctx.fill(outer, with: .color(.black))
            var inner = Path()
            inner.addEllipse(in: CGRect(x: -R*0.135, y: -R*0.135, width: R*0.27, height: R*0.27))
            ctx.fill(inner, with: .color(Color(cgColor: col)))
        }
    }

    private func drawParticles(context: GraphicsContext, size: CGSize, R: CGFloat, cx: CGFloat, cy: CGFloat) {
        for p in particles {
            guard p.age > 0 else { continue }
            let k = CGFloat(p.age / p.life)
            let a = k < 0.2 ? k / 0.2 : 1 - (k - 0.2) / 0.8
            let px = cx + (p.x + p.vx * CGFloat(p.age)) * R * 1.3
            let py = cy + (p.y + p.vy * CGFloat(p.age)) * R * 1.3
            let sz = R * p.size * (1 + k * 0.4)

            var pctx = context
            pctx.translateBy(x: px, y: py)
            pctx.opacity = Double(min(max(a, 0), 1))

            switch p.type {
            case .heart:
                pctx.rotate(by: .radians(sin(CGFloat(p.age) * 6) * 0.3))
                pctx.fill(heartShape(size: sz), with: .color(Color(hex: "#FF4D6D")))
            case .star:
                pctx.rotate(by: .radians(p.rot + CGFloat(p.age) * 2))
                pctx.fill(starShape(outer: sz, inner: sz*0.45), with: .color(Color(hex: "#F7B32B")))
            case .spark:
                pctx.rotate(by: .radians(p.rot))
                pctx.fill(starShape(outer: sz*0.8, inner: sz*0.18), with: .color(.white))
            case .sweat:
                var drop = Path()
                drop.move(to: CGPoint(x: 0, y: -sz))
                drop.addQuadCurve(to: CGPoint(x: 0, y: sz*0.6), control: CGPoint(x: sz*0.8, y: sz*0.2))
                drop.addQuadCurve(to: CGPoint(x: 0, y: -sz), control: CGPoint(x: -sz*0.8, y: sz*0.2))
                pctx.fill(drop, with: .color(Color(hex: "#7CC7FF")))
            case .nota:
                pctx.rotate(by: .radians(p.rot + sin(CGFloat(p.age) * 7) * 0.25))
                pctx.draw(Text(p.size > 0.18 ? "♫" : "♪").font(.system(size: sz * 2.4, weight: .bold))
                            .foregroundColor(Color(red: 0.93, green: 0.95, blue: 1)), at: .zero)
            case .z:
                pctx.draw(Text("z").font(.system(size: sz*1.9, weight: .bold)).foregroundColor(Color(red: 0.82, green: 0.86, blue: 0.92)),
                          at: .zero)
            }
        }
    }

    // MARK: - Tween helpers

    func anim(_ key: String, keys: [TweenKey], onComplete: (() -> Void)? = nil) {
        let current = getProperty(key)
        tweens[key] = Tween(property: key, keys: keys, keyIndex: 0,
                            from: current, startTime: CACurrentMediaTime() * 1000,
                            onComplete: onComplete)
        locks.insert(key)
    }

    private func setTarget(key: String, value: CGFloat) {
        guard !locks.contains(key) else { return }
        switch key {
        case "tint":  tint  += (value - tint)  // immediate target, smoothed in update
        case "tilt":  tgTilt = value
        default: break
        }
    }

    private func setProperty(_ key: String, value: CGFloat) {
        switch key {
        case "yaw":    yaw    = value
        case "pitch":  pitch  = value
        case "roll":   roll   = value
        case "tilt":   tilt   = value
        case "open":   open   = value
        case "sx":     sx     = value
        case "sy":     sy     = value
        case "oy":     oy     = value
        case "ox":     ox     = value
        case "tint":   tint   = value
        case "morph":  morph  = value
        case "hands":  hands  = value
        case "blush":  blush  = value
        case "es":     es     = value
        case "badgeS": badgeS = value
        default: break
        }
    }

    private func getProperty(_ key: String) -> CGFloat {
        switch key {
        case "yaw":    return yaw
        case "pitch":  return pitch
        case "roll":   return roll
        case "tilt":   return tilt
        case "open":   return open
        case "sx":     return sx
        case "sy":     return sy
        case "oy":     return oy
        case "ox":     return ox
        case "tint":   return tint
        case "morph":  return morph
        case "hands":  return hands
        case "blush":  return blush
        case "es":     return es
        case "badgeS": return badgeS
        default:       return 0
        }
    }
}

// MARK: - Math helpers

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b-a) * t }
private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { max(lo, min(hi, v)) }

private func cgColorToTuple(_ c: CGColor) -> (CGFloat, CGFloat, CGFloat) {
    guard let comps = c.components, comps.count >= 3 else { return (1,1,1) }
    return (comps[0], comps[1], comps[2])
}

private func mix3(_ a: (CGFloat,CGFloat,CGFloat), _ b: (CGFloat,CGFloat,CGFloat), _ t: CGFloat) -> (CGFloat,CGFloat,CGFloat) {
    (lerp(a.0,b.0,t), lerp(a.1,b.1,t), lerp(a.2,b.2,t))
}

private func mixColor(_ a: (CGFloat,CGFloat,CGFloat), _ b: (CGFloat,CGFloat,CGFloat), _ t: CGFloat) -> (CGFloat,CGFloat,CGFloat) {
    mix3(a, b, t)
}

private func colorFromTuple(_ t: (CGFloat,CGFloat,CGFloat)) -> Color {
    Color(red: Double(t.0), green: Double(t.1), blue: Double(t.2))
}

private func badgeString(_ b: BadgeType?) -> String {
    guard let b else { return "none" }
    func hex(_ c: CGColor) -> String {
        guard let k = c.components, k.count >= 3 else { return "?" }
        return "\(Int(k[0]*255)).\(Int(k[1]*255)).\(Int(k[2]*255))"
    }
    switch b {
    case .dots(let c):     return "dots-\(hex(c))"
    case .bang(let c):     return "bang-\(hex(c))"
    case .question(let c): return "q-\(hex(c))"
    case .dot(let c):      return "dot-\(hex(c))"
    }
}

private func emoteEyeShape(_ e: BotEmote) -> EyeShape {
    switch e {
    case .love:      return .wink
    case .surprised: return .dot
    case .proud:     return .star
    case .wink:      return .wink
    case .yawn:      return .tired
    case .happy:     return .happy
    case .annoyed:   return .line
    }
}

// MARK: - Shape helpers

private func heartShape(size s: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: s * 0.38))
    p.addCurve(to: CGPoint(x: 0, y: -s * 0.38),
               control1: CGPoint(x: -s * 1.05, y: -s * 0.15),
               control2: CGPoint(x: -s * 0.5,  y: -s * 0.95))
    p.addCurve(to: CGPoint(x: 0, y: s * 0.38),
               control1: CGPoint(x: s * 0.5,   y: -s * 0.95),
               control2: CGPoint(x: s * 1.05,  y: -s * 0.15))
    p.closeSubpath()
    return p
}

private func starShape(outer ro: CGFloat, inner ri: CGFloat) -> Path {
    var p = Path()
    for i in 0..<10 {
        let r = i.isMultiple(of: 2) ? ro : ri
        let a = -.pi/2 + CGFloat(i) * .pi/5
        let pt = CGPoint(x: cos(a) * r, y: sin(a) * r)
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    p.closeSubpath()
    return p
}

// Equatable for BadgeType (needed for comparing)
extension BadgeType: Equatable {
    static func == (lhs: BadgeType, rhs: BadgeType) -> Bool {
        switch (lhs, rhs) {
        case (.dots, .dots): return true
        case (.bang, .bang): return true
        case (.question, .question): return true
        case (.dot, .dot): return true
        default: return false
        }
    }
}

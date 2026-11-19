import SwiftUI

/// Top-level SwiftUI view rendered inside the 720×320 transparent panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(state: state)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Island container

struct IslandContainer: View {
    @ObservedObject var state: AppState
    @ObservedObject private var nivel = NivelService.shared
    @ObservedObject private var arbitro = Arbitro.shared
    @State private var islandWidth:  CGFloat = IslandConst.notchWidth
    @State private var islandHeight: CGFloat = IslandConst.notchHeight
    @State private var cornerRadius: CGFloat = IslandConst.roundedCorner
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0
    @State private var greetNotif: Bool = false

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)

    private var chatPromptHeight: CGFloat { state.chatHeight }

    /// Pixels the content must be pushed down to clear the concave ear transparent area.
    /// = 0 in expanded mode (no ears), = earRadius in compact/notch mode.
    private var earOffset: CGFloat { max(0, -islandTopRadius) }

    var body: some View {
        // Canvas active during drag-over (.upload), post-drop animation (.uploading),
        // AND choose overlay (.choose) — canvas handles the full sequence through user action.
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        let uploadActive = state.mode == .expanded
            && UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)

        let greetingActive = state.mode == .expanded && state.view == .greeting

        return ZStack(alignment: .topLeading) {
            // Black island shape
            IslandShape(width: islandWidth, height: islandHeight,
                        cornerRadius: cornerRadius, topRadius: islandTopRadius)
                .fill(Color.black)

            // Content
            if state.mode == .expanded {
                if greetingActive {
                    // Greeting canvas: fixed 640-wide, centered by offset so x=320 aligns with island center
                    GreetingCanvasView(state: state)
                        .frame(width: IslandConst.expandedWidth, height: 150)
                        .offset(x: (islandWidth - IslandConst.expandedWidth) / 2)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                } else if uploadActive {
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state)
                            .frame(width: islandWidth, height: islandHeight)
                            .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                                  cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        // Header overlaid: canvas CARD_Y=42 aligns exactly with header bottom,
                        // matching normal view proportions (8pt top + 34pt header + card + 10pt bottom).
                        IslandHeader(state: state)
                            .frame(width: islandWidth, height: 34)
                            .offset(y: 8)
                    }
                    .transition(.opacity)
                } else {
                    IslandContentView(state: state)
                        .frame(width: islandWidth, height: islandHeight - earOffset)
                        .offset(y: earOffset)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }

            // Single BotPlacement — always alive in the view tree so spring animations
            // fire from the current position (e.g. choose at 60,101) when canvas deactivates.
            // Hidden during upload canvas or greeting (both draw their own Homie).
            BotPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            CountdownBar(state: state, islandW: islandWidth)

            // Brilho/volume com a ilha aberta: cápsula no rodapé
            if let n = nivel.atual, state.mode == .expanded {
                NivelBarra(nivel: n, compacta: true)
                    .frame(width: 200)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .position(x: islandWidth / 2, y: islandHeight - 16)
                    .transition(.opacity)
            }
            // Ilha fechada: o sinal que o árbitro escolheu para a barra (embaixo do notch)
            if state.mode != .expanded, let b = arbitro.barra {
                b.conteudo
                    .id(b.id)
                    .frame(width: max(0, islandWidth - 106))
                    .position(x: 86 + (islandWidth - 106) / 2, y: islandHeight - 29)
                    .transition(.opacity)
            }

            Group {
                if state.mode == .compact {
                    CompactMiniGrid(state: state)
                        .position(x: islandWidth - 40 - arbitro.larguraExtraCanto / 2, y: state.notchHeight / 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.mode == .compact)
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .onChange(of: state.mode) { oldMode, newMode in
            let shrinking = modeOrder(newMode) < modeOrder(oldMode)
            let anim = shrinking ? closeEase : openSpring
            let (w, h) = islandSize(mode: newMode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            let cr  = newMode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            let tr: CGFloat = 0
            withAnimation(anim) {
                islandWidth      = w
                islandHeight     = (newMode == .expanded && state.view == .prompt) ? chatPromptHeight : h
                cornerRadius     = cr
                islandTopRadius  = tr
            }
        }
        .onChange(of: state.view) { _, newView in
            guard state.mode == .expanded else { return }
            // Deactivate engine if user navigates outside the upload flow
            let uploadViews: Set<IslandView> = [.upload, .uploading, .choose]
            if UploadSequenceEngine.shared.isActive && !uploadViews.contains(newView) {
                UploadSequenceEngine.shared.deactivate()
            }
            let (w, h) = islandSize(mode: .expanded, view: newView,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = newView == .prompt ? chatPromptHeight : h
            }
        }
        .onChange(of: state.chatHeight) { _, h in
            // Puxando contra a trava: segue o dedo. Soltou a trava: mola.
            guard state.mode == .expanded, state.view == .prompt else { return }
            if state.chatAnimate {
                state.chatAnimate = false
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { islandHeight = h }
            } else {
                islandHeight = h
            }
        }
        .onChange(of: state.puxaoAba) { _, p in
            // Elástico de uma tela que cresce: segue o dedo; soltou sem travar, volta com mola
            guard state.mode == .expanded, state.view.cresce else { return }
            if let p {
                islandHeight = p
            } else {
                let (_, h) = islandSize(mode: state.mode, view: state.view,
                                        progress: state.uploadProgress,
                                        nw: state.notchWidth, nh: state.notchHeight)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) { islandHeight = h }
            }
        }
        .onChange(of: state.alturaAba) { _, _ in
            // Tela que cresce pediu mais altura (ou devolveu): anima até lá
            guard state.mode == .expanded, state.view.cresce, state.puxaoAba == nil else { return }
            let (_, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) { islandHeight = h }
        }
        .onAppear {
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            islandWidth      = w
            islandHeight     = state.view == .prompt ? chatPromptHeight : h
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            greetNotif.toggle()
        }
        .onChange(of: arbitro.larguraExtraCanto) { _, _ in
            // Segundo sinal no canto entrou/saiu: a ilha fechada alarga/estreita
            guard state.mode == .compact else { return }
            let (w, _) = islandSize(mode: state.mode, view: state.view, progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) { islandWidth = w }
        }
        .onChange(of: arbitro.barra != nil) { _, mostrando in
            // Ilha fechada cresce para mostrar a barra e volta ao tamanho de antes
            guard state.mode != .expanded else { return }
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(mostrando ? openSpring : closeEase) {
                islandWidth = w
                islandHeight = h
            }
        }
    }

    private func modeOrder(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }
}

// MARK: - Island shape
//
// topRadius > 0  → convex rounded top corners (expanded mode)
// topRadius < 0  → concave ear cutouts, |topRadius| = ear radius (compact/notch mode)
// topRadius = 0  → sharp top corners (transient during animation)

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners
    var topRadius: CGFloat      // see above

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, CGFloat> {
        get { .init(.init(.init(width, height), cornerRadius), topRadius) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cr = max(0, cornerRadius)
        var p  = Path()

        if topRadius >= 0 {
            // ── Convex rounded top corners (expanded) ──────────────────────────
            let tr = min(topRadius, min(width / 2, height / 2))
            p.move(to: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: width - tr, y: 0))
            // Top-right convex corner
            p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge
            p.addLine(to: CGPoint(x: 0, y: tr))
            // Top-left convex corner
            p.addArc(center: CGPoint(x: tr, y: tr), radius: tr,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // ── Concave ear cutouts (compact / notch) ─────────────────────────
            let er = -topRadius   // positive ear radius
            p.move(to: CGPoint(x: 0, y: 0))
            // Top-left ear
            p.addArc(center: CGPoint(x: 0, y: er), radius: er,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Top edge
            p.addLine(to: CGPoint(x: width - er, y: er))
            // Top-right ear
            p.addArc(center: CGPoint(x: width, y: er), radius: er,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge back to top-left corner
            p.addLine(to: CGPoint(x: 0, y: 0))
        }

        p.closeSubpath()
        return p
    }
}

// MARK: - Bot placement helper

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress)
        let canvasSize = diameter / 0.6
        let overhang: CGFloat = 40
        let isUploading = state.view == .uploading

        Group {
            // No glow in uploading mode — the tiny dot doesn't need it
            if state.mode == .expanded && !isUploading {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: botGlowColor(state.effectiveState), location: 0),
                            .init(color: .clear, location: 0.62)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 1.1
                    ))
                    .frame(width: diameter * 2.2, height: diameter * 2.2)
                    .blur(radius: 6)
                    .opacity(botGlowOpacity(state.effectiveState))
                    .position(x: cx, y: cy)
                    .animation(.easeInOut(duration: 0.4), value: state.effectiveState)
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // BotEngine cy = H/2 + 0 + oy*R + R*0.06 ≈ H/2 (body centered in canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotEngine compensates with cy = H/2 + particleOverhang/2 + oy*R + R*0.06.
            if isUploading {
                TimelineView(.animation) { tl in
                    let elapsed: Double = {
                        guard let start = state.uploadStartTime else { return 0 }
                        return tl.date.timeIntervalSince(start)
                    }()
                    let t = min(1.0, max(0, elapsed / state.uploadDuration))
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    BotCanvasView(state: state, particleOverhang: 0)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot ? 0 : opacity)
                        .position(x: uploadCx, y: cy)
                }
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                BotCanvasView(state: state, particleOverhang: overhang)
                    .frame(width: canvasSize, height: canvasSize + overhang)
                    .opacity(state.isDraggingBot ? 0 : opacity)
                    .position(x: cx, y: cy - overhang / 2)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cx)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cy)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvasSize)
                    .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            }
        }
        // Branch switch (uploading ↔ normal) animates with a fast spring: uploading dot
        // scales out at bar-end while normal bot scales in at choose position.
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isUploading)
        // Slap, drag, and hover are handled by the AppKit NSEvent monitor in
        // IslandWindowController — not SwiftUI gestures — so this is safe.
        .allowsHitTesting(false)
    }

    private func botGlowColor(_ s: BotState) -> Color {
        switch s {
        case .working:   return Color(hex: "#3B9EFF")
        case .thinking:  return Color(hex: "#A78BFA")
        case .searching: return Color(hex: "#6366F1")
        case .approval:  return Color(hex: "#F5A524")
        case .error:     return Color(hex: "#F4505E")
        case .finished:  return Color(hex: "#34D399")
        case .ratelimit: return Color(hex: "#F59E0B")
        default:         return Color.white
        }
    }

    private func botGlowOpacity(_ s: BotState) -> Double {
        switch s {
        case .idle, .sleeping: return 0.15
        case .dizzy:           return 0.0
        default:               return 0.65
        }
    }
}

@MainActor
func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double) -> (CGFloat, CGFloat, CGFloat, Double) {
    // Brilho/volume com a ilha fechada: Homie maior, embaixo do notch, à esquerda da barra
    if barraNaIlha(mode) { return (48, islandH - 31, 44, 1) }
    switch mode {
    case .hidden:   return (46, 16, 6, 0)
    case .compact:  return (40, 16, 20, 1)
    case .expanded:
        // Aba de módulo alta: o Homie fica pequeno no canto de cima, liberando a largura
        // Abas de módulo e "Vira task?" crescem como o mesmo cartão: o Homie fica onde estava.
        let mesmoCartao = view == .sugestao || view == .modulo
        if view.cresce, AppState.shared.alturaAba != nil, !mesmoCartao { return (28, 60, 26, 1) }
        let layout = IslandConst.layout(view)
        // Tela que cresce (inclusive durante o elástico): o Homie não se mexe
        let islandH = mesmoCartao ? layout.height : islandH
        let diameter = layout.botDiameter
        // Uploading: Homie dot rides the leading edge of the progress fill.
        // Bar in island coords: left=36, width=526. cx = 36 + progress*526 (dot center at fill right edge).
        // cy comes from ViewLayout.botY (bar center in island coords).
        if view == .uploading {
            let cx = 36 + CGFloat(uploadProgress) * 526
            return (cx, layout.botY ?? 103, diameter, 1)
        }
        let cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = fixedY
        } else {
            // Center of the fixed 84pt card (VStack top=8, header=34 → content starts at y=42)
            let headerBottom: CGFloat = 42
            let cardH: CGFloat = 84
            cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2
        }
        return (cx, cy, diameter, 1)
    }
}

// MARK: - Countdown bar

struct CountdownBar: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    @State private var barWidth: CGFloat = 0
    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: barWidth, height: 2)
                .cornerRadius(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onAppear { if state.mode == .expanded { startTimer() } }
        .onChange(of: state.mode) { _, modo in
            // Só conta com a ilha aberta; fechada, nenhum timer.
            if modo == .expanded { startTimer() } else { stopTimer(); barWidth = 0 }
        }
        .onDisappear { stopTimer() }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            updateBar()
        }
    }

    private func updateBar() {
        guard state.mode == .expanded && !state.isPinned && !state.fixado else {
            barWidth = 0
            return
        }
        let autoClose = state.autoCloseInterval
        let window = min(10.0, autoClose * 0.6)
        let elapsed = Date.now.timeIntervalSince(state.lastActivity)
        let remaining = autoClose - elapsed
        if remaining < window {
            barWidth = max(0, CGFloat(remaining / window) * 160)
        } else {
            barWidth = 0
        }
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            IslandHeader(state: state)
                .frame(height: 34)
                .opacity(state.view == .confused ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: state.view == .confused)

            // Só a aba da frente fica montada (antes eram todas, invisíveis). Troca de aba:
            // a que sai some depressa e a que entra cresce de 97 %, como antes.
            ZStack {
                let v = state.view
                // Chat e e-mail ocupam a altura que houver; o resto, o cartão fixo de 98 pt
                // Tela que cresce: o cartão acompanha a borda de baixo da ilha (elástico e mola) com o
                // topo parado — na altura normal dá os mesmos 98 pt, centrado como os outros
                let cresce = v.cresce && ElasticoIlha.alta(v, modulo: state.moduloAberto) != nil
                let isTall = v == .prompt || v == .mail || cresce || (v.cresce && state.alturaAba != nil)
                IslandViewContent(view: v, state: state)
                    .id(v == .modulo ? "modulo.\(state.moduloAberto ?? "")" : v.rawValue)
                    .frame(maxWidth: .infinity)
                    .frame(height: isTall ? nil : 98)
                    .frame(maxHeight: isTall ? .infinity : nil)
                    .padding(.vertical, cresce ? 5 : 0)
                    .environment(\.telaVisivel, state.mode == .expanded)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.97))
                            .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(0.16)),
                        removal: .opacity.animation(.easeIn(duration: 0.16))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .foregroundColor(Color(hex: "#F5F6F8"))
    }
}

// MARK: - Island header (tabs + icons)

struct IslandHeader: View {
    @ObservedObject var state: AppState
    @ObservedObject private var registro = Registro.shared

    // O notch físico (câmera e sensores) esconde o meio do cabeçalho: nada clicável ali.
    // Esquerda da câmera: as abas fixas. Direita: módulos favoritos + grade + ações.
    private let larguraAba: CGFloat = 35          // botão 30 + espaço 5
    private let larguraAcoes: CGFloat = 92        // fixar, ajustes, som
    private var folgaCamera: CGFloat { 12 }       // margem de cada lado do notch

    var body: some View {
        GeometryReader { g in
            let notch = state.notchWidth + folgaCamera * 2
            let lado = max(0, (g.size.width - notch) / 2)
            // Quantos favoritos cabem à direita, guardando lugar para a grade
            let cabem = max(0, Int((lado - 16 - larguraAcoes - larguraAba) / larguraAba))
            let favoritos = registro.favoritos(max: cabem)
            let _ = DispatchQueue.main.async {
                let ids = favoritos.map(\.id)
                if registro.noTopo != ids { registro.noTopo = ids }
            }
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    TabButton(icon: "house.fill", view: .overview, state: state)
                    TabButton(icon: "bubble.left.fill", view: .prompt, state: state, preAction: {
                        if state.promptContext == nil {
                            state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
                        }
                    })
                    TabButton(icon: "music.note", view: .media, state: state, preAction: {
                        MediaService.shared.refresh()
                    })
                    TabButton(icon: "plus", view: .upload, state: state)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .frame(width: lado, alignment: .leading)

                Color.clear.frame(width: notch)   // embaixo da câmera

                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    ForEach(favoritos, id: \.id) { m in
                        TabModulo(icone: m.icone, id: m.id, nome: m.nome, state: state)
                    }
                    if !registro.comAba.isEmpty {
                        TabGrade(state: state, favoritos: favoritos.map(\.id))
                    }
                    acoes.padding(.leading, 9)
                }
                .padding(.trailing, 16)
                .frame(width: lado, alignment: .trailing)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var acoes: some View {
        HStack(spacing: 14) {
            // Fixar: a ilha não fecha sozinha enquanto estiver ligado
            Button(action: { state.fixado.toggle() }) {
                Image(systemName: state.fixado ? "pin.fill" : "pin")
                    .font(.system(size: 13))
                    .rotationEffect(.degrees(45))
                    .foregroundColor(state.fixado ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
            .help(state.fixado ? "Soltar (volta a fechar sozinho)" : "Fixar aberto")

            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    state.view = .settings
                }
            }) {
                Image(systemName: state.view == .settings ? "gearshape.fill" : "gearshape")
                    .font(.system(size: 14))
                    .foregroundColor(state.view == .settings ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)

            Button(action: { state.soundEnabled.toggle() }) {
                Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 14))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .buttonStyle(.plain)
        }
    }
}

/// Botão da grade de módulos. Aceso na grade e quando o módulo aberto não tem atalho próprio
/// (aí mostra o ícone dele, para o Hugo saber onde está).
struct TabGrade: View {
    @ObservedObject var state: AppState
    let favoritos: [String]
    @State private var isHovered = false

    private var moduloForaDosFavoritos: (any Modulo)? {
        guard state.view == .modulo, let id = state.moduloAberto, !favoritos.contains(id) else { return nil }
        return Registro.shared.modulo(id)
    }
    private var isOn: Bool { state.view == .modulos || moduloForaDosFavoritos != nil }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .modulos }
        }) {
            Image(systemName: moduloForaDosFavoritos?.icone ?? "square.grid.2x2")
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(isOn ? Color(hex: "#1D1F23") : isHovered ? Color.white.opacity(0.07) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Todos os módulos")
        .onHover { isHovered = $0 }
    }
}

/// Grade com todos os módulos que têm aba: um clique abre o módulo.
struct GradeModulos: View {
    @ObservedObject var state: AppState
    @ObservedObject private var registro = Registro.shared
    @State private var sobre: String?

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Só os que não têm atalho no topo (não faz sentido o mesmo módulo em dois lugares)
                    ForEach(registro.comAba.filter { !registro.noTopo.contains($0.id) }, id: \.id) { m in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                state.moduloAberto = m.id
                                state.view = .modulo
                            }
                        }) {
                            VStack(spacing: 7) {
                                Image(systemName: m.icone).font(.system(size: 20))
                                    .frame(height: 24)
                                Text(m.nome).font(.system(size: 11, weight: .medium)).lineLimit(1)
                            }
                            .foregroundColor(Color(hex: sobre == m.id ? "#F5F6F8" : "#C9CDD3"))
                            .frame(width: 76, height: 70)
                            .background(Color.white.opacity(sobre == m.id ? 0.10 : 0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .onHover { sobre = $0 ? m.id : (sobre == m.id ? nil : sobre) }
                    }
                    Button(action: { Central.abrir() }) {
                        VStack(spacing: 7) {
                            Image(systemName: "slider.horizontal.3").font(.system(size: 18)).frame(height: 24)
                            Text("Ajustes").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 76, height: 70)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Ligar, desligar e escolher os atalhos nos Ajustes")
                }
                .padding(.horizontal, 2)
            }
            .padding(.leading, 108)
            .padding(.trailing, 14)
        }
    }
}

struct TabButton: View {
    let icon: String
    let view: IslandView
    @ObservedObject var state: AppState
    var preAction: (() -> Void)? = nil
    @State private var isHovered = false

    private var isOn: Bool {
        if view == .overview { return state.view == .overview || state.view == .empty }
        return state.view == view
    }

    var body: some View {
        Button(action: {
            preAction?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = view
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Aba de um módulo no cabeçalho (mesmo visual do TabButton).
struct TabModulo: View {
    let icone: String
    let id: String
    let nome: String
    @ObservedObject var state: AppState
    @State private var isHovered = false

    private var isOn: Bool { state.view == .modulo && state.moduloAberto == id }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.moduloAberto = id
                state.view = .modulo
            }
        }) {
            Image(systemName: icone)
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(nome)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Compact mini mochi grid (2×2 to the right of the notch)

struct CompactMiniGrid: View {
    @ObservedObject var state: AppState

    private var others: [AgentTask] {
        Array(state.tasks.filter { $0.id != state.focusId && $0.ativa }.prefix(4))
    }

    @ObservedObject private var arbitro = Arbitro.shared

    var body: some View {
        // Sinais no canto (indicador do Mac, capa da música…): entram no lugar dos Homies das
        // outras sessões; até dois lado a lado.
        let cantos = arbitro.cantos
        if !cantos.isEmpty {
            HStack(spacing: 6) {
                ForEach(cantos, id: \.id) { c in
                    c.conteudo.id(c.id)
                        .frame(width: 28, height: 28)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        } else {
            miniHomies
        }
    }

    @ViewBuilder private var miniHomies: some View {
        let cols = [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)]
        // Um relógio só para todos os mini-Homies: cada relógio a mais é um ciclo de
        // atualização da janela a mais.
        TimelineView(.animation(minimumInterval: Quadros.mini)) { tl in
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(others) { task in
                    MiniBotCanvasView(task: task, tempo: tl.date)
                        .frame(width: 12 / 0.6, height: 12 / 0.6)
                        .frame(width: 12, height: 12, alignment: .center)
                }
            }
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        let r = Double((val >> 16) & 0xFF) / 255
        let g = Double((val >> 8)  & 0xFF) / 255
        let b = Double( val        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

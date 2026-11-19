import SwiftUI
import AppKit

// O campo de endereço que sugere, como o do Arc: completa em linha o site mais provável (o
// resto fica selecionado — continuar digitando substitui), e mostra embaixo a lista: o site,
// buscar o texto, aba já aberta ("Ir para a aba"), páginas do histórico e, quando nada
// visitado casa, buscas sugeridas. ↑ ↓ andam, Enter vai na linha marcada, Tab aceita o que
// foi completado, Esc fecha a lista (e, de novo, sai do campo).
// As regras (o que completar, a ordem) são puras: `Politicas/SugestoesEndereco.swift`.

/// O estado da lista de sugestões de um campo de endereço.
@MainActor
final class SugestoesModelo: ObservableObject {
    @Published private(set) var itens: [SugestaoNav] = []
    @Published private(set) var indice = 0
    @Published private(set) var aberta = false
    /// O que o campo completou em linha (nil = nada).
    private(set) var completar: CompletarNav?
    /// O que foi digitado de verdade (sem o completado).
    private(set) var digitado = ""

    /// A aba que está na tela (não é sugerida como "Ir para a aba").
    var abaAtual: String?

    private var buscas: [String] = []
    private var pedido: Task<Void, Never>?

    var escolhida: SugestaoNav? { aberta && itens.indices.contains(indice) ? itens[indice] : nil }
    /// A linha marcada é a do site completado?
    var marcadaCompleta: Bool { completar != nil && indice == 0 }

    private var abasAbertas: [AbaAbertaNav] {
        // Abas de outra sessão não são oferecidas: o espaço avulso é só dela.
        let foco = NavegadorServico.shared.espacoEmFoco
        return NavegadorServico.shared.espacos.filter { !$0.daSessao || $0.id == foco }.flatMap { e in
            e.abas.map { AbaAbertaNav(id: $0.id, url: $0.url, titulo: $0.titulo, espaco: e.id) }
        }
    }

    /// O texto mudou. `completando` = pode completar em linha (falso ao apagar).
    func digitou(_ texto: String, completando: Bool) {
        digitado = texto
        let visitas = HistoricoNav.shared.visitas
        let agora = Date()
        completar = completando ? SugestoesEndereco.completar(texto, visitas: visitas, agora: agora) : nil
        // As buscas sugeridas de antes só ficam se ainda forem do mesmo começo de texto.
        buscas = []
        montar()

        pedido?.cancel()
        let abas = abasAbertas
        guard BuscasSugeridas.ligado, !CaptureTool.ativo,
              SugestoesEndereco.querBuscas(texto, visitas: visitas, abas: abas, agora: agora) else { return }
        pedido = Task { [weak self] in
            // Espera uma pausa na digitação: não manda letra por letra.
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            let achadas = await BuscasSugeridas.buscar(texto.trimmingCharacters(in: .whitespaces))
            guard !Task.isCancelled, let self, self.digitado == texto, self.aberta else { return }
            self.buscas = achadas
            self.montar(mantendoIndice: true)
        }
    }

    private func montar(mantendoIndice: Bool = false) {
        var lista = SugestoesEndereco.montar(texto: digitado, visitas: HistoricoNav.shared.visitas, abas: abasAbertas,
                                             buscas: buscas, abaAtual: abaAtual, agora: Date())
        // Sem completar em linha (apagando), o Enter faz o que foi digitado: o site não passa na frente.
        if completar == nil, let i = lista.firstIndex(where: { $0.tipo == .endereco || $0.tipo == .buscar }), i > 0 {
            lista.insert(lista.remove(at: i), at: 0)
        }
        itens = lista
        indice = mantendoIndice ? min(indice, max(0, lista.count - 1)) : 0
        aberta = !lista.isEmpty
    }

    func mover(_ passo: Int) {
        guard aberta, !itens.isEmpty else { return }
        indice = (indice + passo + itens.count) % itens.count
    }

    /// Tab: o completado vira digitado.
    func aceitar() -> String? {
        guard let c = completar else { return nil }
        let inteiro = digitado + c.resto
        digitou(inteiro, completando: false)
        return inteiro
    }

    func fechar() {
        pedido?.cancel()
        aberta = false
        itens = []
        indice = 0
        completar = nil
        buscas = []
    }

    /// Lista de exemplo para as capturas (nada vem da rede).
    func exemplo(_ texto: String) {
        HistoricoNav.shared.exemploParaCaptura()
        digitou(texto, completando: true)
    }
}

// MARK: - O campo (AppKit, para completar em linha com o resto selecionado)

struct CampoEndereco: NSViewRepresentable {
    /// O que o campo mostra quando o cursor não está nele (o endereço da página).
    let endereco: String
    @ObservedObject var modelo: SugestoesModelo
    /// Muda → o campo ganha o cursor, com tudo selecionado.
    let pedirFoco: Int
    /// O campo começa vazio ao ganhar o cursor (aba nova).
    let vazioAoFocar: Bool
    let aoFocar: (Bool) -> Void
    /// Enter: a linha marcada, ou o texto digitado se não há lista.
    let aoEnviar: (SugestaoNav?, String) -> Void

    func makeCoordinator() -> Coordenador { Coordenador(self) }

    func makeNSView(context: Context) -> CampoNS {
        let f = CampoNS()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 12.5)
        f.textColor = NSColor(Tema.texto)
        f.lineBreakMode = .byTruncatingTail
        f.cell?.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.placeholderAttributedString = NSAttributedString(
            string: "Buscar ou digitar endereço",
            attributes: [.foregroundColor: NSColor(Tema.texto3), .font: NSFont.systemFont(ofSize: 12.5)])
        f.delegate = context.coordinator
        f.aoFocar = { [weak c = context.coordinator] in c?.focou() }
        f.stringValue = endereco
        context.coordinator.campo = f
        context.coordinator.focoVisto = pedirFoco
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        f.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return f
    }

    func updateNSView(_ f: CampoNS, context: Context) {
        let c = context.coordinator
        c.pai = self
        if !c.focado, f.stringValue != endereco { f.stringValue = endereco }
        if c.focoVisto != pedirFoco {
            c.focoVisto = pedirFoco
            DispatchQueue.main.async {
                guard let janela = f.window else { return }
                if vazioAoFocar { f.stringValue = "" }
                if c.focado { f.currentEditor()?.selectAll(nil) } else { janela.makeFirstResponder(f) }
            }
        }
    }

    /// O NSTextField que avisa quando ganha o cursor.
    final class CampoNS: NSTextField {
        var aoFocar: (() -> Void)?

        override func becomeFirstResponder() -> Bool {
            let ok = super.becomeFirstResponder()
            if ok { aoFocar?() }
            return ok
        }
    }

    @MainActor
    final class Coordenador: NSObject, NSTextFieldDelegate {
        var pai: CampoEndereco
        weak var campo: CampoNS?
        var focado = false
        var focoVisto = 0
        /// O que o Hugo digitou de verdade (o campo pode mostrar isso + o completado).
        private var digitado = ""

        init(_ pai: CampoEndereco) { self.pai = pai }

        private var editor: NSTextView? { campo?.currentEditor() as? NSTextView }

        func focou() {
            guard !focado else { return }
            focado = true
            digitado = campo?.stringValue ?? ""
            pai.aoFocar(true)
            // Com o cursor no campo, o endereço inteiro fica selecionado: digitar substitui.
            DispatchQueue.main.async { [weak self] in self?.campo?.currentEditor()?.selectAll(nil) }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard focado else { return }
            focado = false
            pai.aoFocar(false)
            campo?.stringValue = pai.endereco
            // Um clique numa linha da lista tira o cursor do campo antes de chegar nela.
            let modelo = pai.modelo
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                if self?.focado != true { modelo.fechar() }
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let campo, let editor else { return }
            let s = campo.stringValue
            // Acento em composição (´ + a): mexer no texto agora quebraria a letra.
            if editor.hasMarkedText() {
                digitado = s
                pai.modelo.digitou(s, completando: false)
                return
            }
            // Apagou (inclusive o completado, que estava selecionado): não completa de novo.
            let apagando = s.count <= digitado.count && digitado.hasPrefix(s)
            let noFim = editor.selectedRange().location == (s as NSString).length
            digitado = s
            pai.modelo.digitou(s, completando: !apagando && noFim)
            mostrarCompletado()
        }

        /// Põe no campo o digitado + o resto completado, com o resto selecionado.
        private func mostrarCompletado() {
            guard let editor else { return }
            let base = digitado as NSString
            if pai.modelo.marcadaCompleta, let c = pai.modelo.completar {
                editor.string = digitado + c.resto
                editor.setSelectedRange(NSRange(location: base.length, length: (c.resto as NSString).length))
            } else if editor.string != digitado {
                editor.string = digitado
                editor.setSelectedRange(NSRange(location: base.length, length: 0))
            }
        }

        private func aceitar() -> Bool {
            guard pai.modelo.marcadaCompleta, let inteiro = pai.modelo.aceitar(), let editor else { return false }
            digitado = inteiro
            editor.string = inteiro
            editor.setSelectedRange(NSRange(location: (inteiro as NSString).length, length: 0))
            return true
        }

        private func sair() {
            pai.modelo.fechar()
            campo?.window?.makeFirstResponder(nil)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy comando: Selector) -> Bool {
            let m = pai.modelo
            switch comando {
            case #selector(NSResponder.moveDown(_:)):
                guard m.aberta else { return false }
                m.mover(1); mostrarCompletado()
            case #selector(NSResponder.moveUp(_:)):
                guard m.aberta else { return false }
                m.mover(-1); mostrarCompletado()
            case #selector(NSResponder.insertNewline(_:)):
                let escolhida = m.escolhida
                let texto = digitado
                sair()
                pai.aoEnviar(escolhida, texto)
            case #selector(NSResponder.cancelOperation(_:)):
                if m.aberta {
                    // Primeiro Esc: fecha a lista e tira o completado. O segundo sai do campo.
                    m.fechar()
                    mostrarCompletado()
                } else {
                    sair()
                }
            case #selector(NSResponder.insertTab(_:)):
                return aceitar()
            case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveToEndOfLine(_:)),
                 #selector(NSResponder.moveToRightEndOfLine(_:)):
                return aceitar()
            default:
                return false
            }
            return true
        }
    }
}

// MARK: - A lista

struct ListaSugestoes: View {
    @ObservedObject var modelo: SugestoesModelo
    let escolher: (SugestaoNav) -> Void

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(modelo.itens.enumerated()), id: \.element.id) { i, s in
                LinhaSugestao(sugestao: s, marcada: i == modelo.indice) { escolher(s) }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Tema.elevado))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Tema.bordaForte))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }
}

private struct LinhaSugestao: View {
    let sugestao: SugestaoNav
    let marcada: Bool
    let acao: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: acao) {
            HStack(spacing: 9) {
                icone.frame(width: 16, height: 16)
                Text(sugestao.titulo)
                    .font(.system(size: 12.5, weight: marcada ? .medium : .regular))
                    .foregroundStyle(Tema.texto)
                    .lineLimit(1)
                    .layoutPriority(1)
                if !detalhe.isEmpty {
                    Text("— " + detalhe)
                        .font(.system(size: 12))
                        .foregroundStyle(Tema.texto3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                if sugestao.tipo == .aba {
                    HStack(spacing: 4) {
                        Text("Ir para a aba")
                        Image(systemName: "arrow.right").font(.system(size: 9.5, weight: .semibold))
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(marcada ? Tema.texto : Tema.texto2)
                    .padding(.horizontal, 8).frame(height: 20)
                    .background(Pilula().fill(Color.white.opacity(marcada ? 0.12 : 0.06)))
                    .fixedSize()
                } else if marcada {
                    Image(systemName: "return").font(.system(size: 10, weight: .medium)).foregroundStyle(Tema.texto3)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Tema.raioLinha, style: .continuous)
                .fill(marcada ? Tema.selecao : hover ? Tema.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: Tema.raioLinha))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }

    private var detalhe: String {
        switch sugestao.tipo {
        case .site: return sugestao.titulo == sugestao.detalhe ? "" : sugestao.detalhe
        case .buscar: return "Buscar no Google"
        case .busca: return ""
        default: return sugestao.detalhe
        }
    }

    @ViewBuilder
    private var icone: some View {
        switch sugestao.tipo {
        case .buscar, .busca:
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .medium)).foregroundStyle(Tema.texto3)
        case .endereco:
            Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(Tema.texto3)
        case .pagina:
            Favicon(url: sugestao.destino)
        case .site, .aba:
            Favicon(url: sugestao.destino)
        }
    }
}

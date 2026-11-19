import SwiftUI
import AppKit
import WebKit

// A tela do navegador do Crew, no desenho do Safari: em cima a barra de endereço; logo abaixo
// as abas lado a lado, dividindo a largura (fixadas à esquerda, só com o ícone); embaixo, a
// página inteira. Com uma aba só a faixa de abas some. Os espaços (um por projeto) ficam no
// menu de abas da barra.

/// A sessão dona de um navegador aberto ao lado dela.
struct SessaoDoNavegador: Equatable {
    var id: String
    var nome: String
    var cor: String?
}

struct NavegadorView: View {
    /// Pasta raiz do projeto cujo espaço abre (nil = Geral).
    let projeto: String?
    /// Aberto ao lado de uma sessão: o espaço avulso dela (id da sessão, nome e cor).
    var sessao: SessaoDoNavegador? = nil
    /// Fecha o painel (quando o navegador está ao lado de uma sessão).
    var aoFechar: (() -> Void)? = nil

    @ObservedObject private var s = NavegadorServico.shared
    @Environment(\.recuoTitulo) private var recuo
    @State private var espacoId = NavegadorServico.geral
    @StateObject private var sugestoes = SugestoesModelo()

    private var espaco: EspacoNav? { s.espaco(espacoId) }
    private var ativa: AbaNav? { espaco.flatMap { e in e.abas.first { $0.id == e.ativa } } }
    private var lado: AbaNav? { espaco.flatMap { e in e.abas.first { $0.id == e.lado && $0.id != e.ativa } } }

    var body: some View {
        VStack(spacing: 0) {
            BarraEndereco(espacoId: $espacoId, aba: ativa, aoFechar: aoFechar, sugestoes: sugestoes,
                          escolher: { escolher($0, texto: $1) })
                .padding(.leading, recuo)
            if (espaco?.abas.count ?? 0) > 1 {
                FaixaAbas(espacoId: $espacoId)
            }
            Fio()
            pagina
                // A lista de sugestões cai da barra, por cima da página.
                .overlay(alignment: .top) {
                    if sugestoes.aberta {
                        ListaSugestoes(modelo: sugestoes) { escolher($0, texto: "") }
                            .frame(maxWidth: 640)
                            .padding(.horizontal, 12).padding(.top, 4)
                    }
                }
        }
        .background(Tema.fundo)
        .overlay(alignment: .bottom) { avisoView }
        .overlay { if s.importandoArc { ImportarArcView { s.importandoArc = false } } }
        .onAppear { entrar() }
        .onChange(of: projeto) { _, _ in entrar() }
        .onChange(of: sessao) { _, _ in entrar() }
        .onChange(of: espacoId) { _, id in s.espacoEmFoco = id }
        .onReceive(NotificationCenter.default.publisher(for: .navegadorNoEspaco)) { n in
            guard projeto == nil, sessao == nil, let e = n.object as? String, s.espaco(e) != nil else { return }
            espacoId = e
            s.espacoPedido = nil
        }
    }

    private func entrar() {
        if let sessao {
            espacoId = s.garantir(sessao: sessao.id, nome: sessao.nome, cor: sessao.cor)
            s.espacoEmFoco = espacoId
            return
        }
        espacoId = s.garantir(projeto: projeto)
        // Pedido de fora (comando universal: "ir para a aba"): o espaço da aba pedida.
        if projeto == nil, let e = s.espacoPedido, s.espaco(e) != nil { espacoId = e }
        if projeto == nil { s.espacoPedido = nil }
        s.espacoEmFoco = espacoId
        if CaptureTool.ativo, let t = s.digitandoNoExemplo { sugestoes.exemplo(t) }
    }

    /// Enter no campo ou clique numa linha: vai para o site, busca ou troca para a aba aberta.
    private func escolher(_ sugestao: SugestaoNav?, texto: String) {
        sugestoes.fechar()
        NSApp.keyWindow?.makeFirstResponder(nil)
        guard let sugestao else {
            s.navegar(texto, em: espacoId)
            return
        }
        switch sugestao.tipo {
        case .aba:
            // A aba já existe: vai para ela (no espaço dela) em vez de abrir outra.
            if let aba = sugestao.aba {
                if let e = sugestao.espaco, e != espacoId { espacoId = e }
                s.ativar(aba)
            }
        case .buscar, .busca:
            if let u = NavegadorServico.busca(sugestao.destino) { s.navegar(para: u, em: espacoId) }
        case .site, .pagina, .endereco:
            s.navegar(sugestao.destino, em: espacoId)
        }
    }

    @ViewBuilder
    private var pagina: some View {
        if let ativa {
            HStack(spacing: 0) {
                PaginaAba(viva: s.viva(ativa))
                if let lado {
                    Rectangle().fill(Tema.borda).frame(width: 1)
                    VStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Favicon(url: lado.url)
                            Text(lado.titulo).font(.system(size: 11.5)).foregroundStyle(Tema.texto2).lineLimit(1)
                            Spacer()
                            BotaoIcone(icone: "arrow.left.arrow.right", ajuda: "Trocar de lado", lado: 22) { s.ativar(lado.id); s.alternarLado(ativa.id) }
                            BotaoIcone(icone: "xmark", ajuda: "Tirar do lado (a aba continua aberta)", lado: 22) { s.alternarLado(lado.id) }
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                        Fio()
                        PaginaAba(viva: s.viva(lado))
                    }
                }
            }
        } else {
            vazio
        }
    }

    /// Sem aba aberta: o Homie e as fixadas do espaço.
    private var vazio: some View {
        VStack(spacing: 14) {
            HomieVivo(estado: .idle, tamanho: 110)
                .frame(width: 110, height: 88)
            Text("Para onde?")
                .font(Tema.titulo(20, .bold)).foregroundStyle(Tema.texto)
            Text("Digite um endereço ou uma busca na barra (⌘L).")
                .font(.system(size: 13)).foregroundStyle(Tema.texto2)
            let fixadas = espaco?.abas.filter(\.fixada) ?? []
            if !fixadas.isEmpty {
                FluxoCrew(espaco: 8) {
                    ForEach(fixadas) { a in
                        BotaoChip(icone: "pin.fill", texto: a.titulo, cor: Tema.texto2) { s.ativar(a.id) }
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { s.focarCampo += 1 }
    }

    @ViewBuilder
    private var avisoView: some View {
        if let a = s.aviso {
            Button {
                if let f = a.arquivo { NSWorkspace.shared.activateFileViewerSelecting([f]) }
                s.aviso = nil
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: a.arquivo != nil ? "arrow.down.circle.fill" : "info.circle.fill").font(.system(size: 12))
                    Text(a.texto).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if a.arquivo != nil { Text("· mostrar no Finder").font(.system(size: 11.5)).foregroundStyle(Tema.texto3) }
                }
                .foregroundStyle(Tema.texto)
                .padding(.horizontal, 14).frame(height: 34)
                .background(Pilula().fill(Tema.elevado))
                .overlay(Pilula().strokeBorder(Tema.bordaForte))
                .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
            .task(id: a) {
                try? await Task.sleep(for: .seconds(a.arquivo != nil ? 6 : 2.5))
                if !Task.isCancelled, s.aviso == a { s.aviso = nil }
            }
        }
    }
}

// MARK: - Página

/// A página de uma aba: a barra fina de progresso, o erro (se não carregou) e o WebKit.
private struct PaginaAba: View {
    @ObservedObject var viva: AbaViva

    var body: some View {
        ZStack(alignment: .top) {
            if let erro = viva.erro {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 24, weight: .light)).foregroundStyle(Tema.texto3)
                    Text("A página não abriu").font(Tema.titulo(16)).foregroundStyle(Tema.texto)
                    Text(erro).font(.system(size: 12.5)).foregroundStyle(Tema.texto2).multilineTextAlignment(.center)
                    BotaoPilula(titulo: "Tentar de novo", icone: "arrow.clockwise", altura: 30) {
                        viva.erro = nil
                        viva.web.reload()
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                WebHospedeiro(web: viva.web)
            }
            if viva.carregando {
                GeometryReader { g in
                    Rectangle().fill(Tema.azul)
                        .frame(width: g.size.width * max(0.06, viva.progresso), height: 2)
                        .animation(.easeOut(duration: 0.2), value: viva.progresso)
                }
                .frame(height: 2)
                .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Segura o WKWebView da aba. Trocar de aba troca a página dentro do mesmo suporte: a que sai
/// continua viva (não recarrega ao voltar).
private struct WebHospedeiro: NSViewRepresentable {
    let web: WKWebView

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        v.wantsLayer = true
        por(web, em: v)
        return v
    }

    func updateNSView(_ v: NSView, context: Context) {
        if v.subviews.first !== web { por(web, em: v) }
    }

    private func por(_ web: WKWebView, em v: NSView) {
        v.subviews.forEach { $0.removeFromSuperview() }
        web.removeFromSuperview()
        web.frame = v.bounds
        web.autoresizingMask = [.width, .height]
        v.addSubview(web)
    }
}

// MARK: - Barra de endereço

private struct BarraEndereco: View {
    @Binding var espacoId: String
    let aba: AbaNav?
    var aoFechar: (() -> Void)?
    @ObservedObject var sugestoes: SugestoesModelo
    let escolher: (SugestaoNav?, String) -> Void

    @ObservedObject private var s = NavegadorServico.shared
    @State private var texto = ""
    @State private var busca = ""
    /// O cursor está no campo de endereço.
    @State private var campo = false
    @FocusState private var campoBusca: Bool

    private var viva: AbaViva? { aba.map { s.viva($0) } }

    var body: some View {
        HStack(spacing: 4) {
            BotaoIconeMenu(icone: "square.on.square", ajuda: "Abas e espaços") { menuAbas() }
            if let viva {
                BotoesDeNavegar(viva: viva)
            }
            HStack(spacing: 7) {
                Image(systemName: icone)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Tema.texto3)
                if CaptureTool.ativo, let t = s.digitandoNoExemplo {
                    // Nas capturas não há cursor: o digitado e o completado (selecionado) são desenhados.
                    HStack(spacing: 0) {
                        Text(t).foregroundStyle(Tema.texto)
                        Text(sugestoes.completar?.resto ?? "").foregroundStyle(Tema.texto)
                            .background(Tema.azul.opacity(0.35))
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12.5))
                } else {
                    CampoEndereco(endereco: texto, modelo: sugestoes, pedirFoco: s.focarCampo,
                                  vazioAoFocar: aba == nil, aoFocar: { campo = $0 }, aoEnviar: escolher)
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 30)
            .background(Pilula().fill(Color.white.opacity(0.05)))
            .overlay(Pilula().strokeBorder(campo ? Tema.bordaForte : Tema.borda))
            if s.buscando { campoDeBusca }
            if let viva {
                BotaoIcone(icone: "key", ajuda: "Preencher com as Senhas do macOS (⇧⌘P) — com o cursor no campo da página") {
                    s.preencherSenha(viva.web)
                }
            }
            BotaoIconeMenu(icone: "ellipsis", ajuda: "Mais") { menuDaPagina() }
            BotaoIcone(icone: "plus", ajuda: "Nova aba (⌘T)") { s.novaAba(espacoId) }
            if let aoFechar {
                BotaoIcone(icone: "xmark", ajuda: "Fechar o navegador (as abas ficam guardadas)", acao: aoFechar)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .onAppear { mostrarEndereco(); sugestoes.abaAtual = aba?.id }
        .onChange(of: aba?.id) { _, id in mostrarEndereco(); sugestoes.abaAtual = id }
        .onChange(of: aba?.url) { _, _ in if !campo { mostrarEndereco() } }
        .onChange(of: campo) { _, f in
            s.campoFocado = f || campoBusca
            if !f { mostrarEndereco() }
        }
        .onChange(of: campoBusca) { _, f in s.campoFocado = f || campo }
        // (O cursor vai para o campo dentro do `CampoEndereco`, que vê `s.focarCampo` mudar.)
        .onChange(of: aba == nil) { _, semAba in if semAba { texto = "" } }
        .onChange(of: s.buscando) { _, b in if b { campoBusca = true } }
        .onDisappear { s.campoFocado = false }
    }

    private var icone: String {
        guard let u = aba?.url, !campo else { return "magnifyingglass" }
        return u.hasPrefix("https://") ? "lock.fill" : u.hasPrefix("http://") ? "exclamationmark.triangle" : "magnifyingglass"
    }

    private func mostrarEndereco() {
        texto = viva?.url?.absoluteString ?? aba?.url ?? ""
        if texto == "about:blank" { texto = "" }
    }

    private var campoDeBusca: some View {
        HStack(spacing: 5) {
            TextField("", text: $busca, prompt: Text("Buscar na página").foregroundStyle(Tema.texto3))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Tema.texto)
                .focused($campoBusca)
                .frame(width: 130)
                .onSubmit { procurar(paraTras: NSEvent.modifierFlags.contains(.shift)) }
                .onExitCommand { s.buscando = false }
            BotaoIcone(icone: "chevron.up", ajuda: "Anterior (⇧Enter)", lado: 20) { procurar(paraTras: true) }
            BotaoIcone(icone: "chevron.down", ajuda: "Próxima (Enter)", lado: 20) { procurar(paraTras: false) }
            BotaoIcone(icone: "xmark", ajuda: "Fechar a busca (Esc)", lado: 20) { s.buscando = false }
        }
        .padding(.leading, 10).padding(.trailing, 4)
        .frame(height: 30)
        .background(Pilula().fill(Color.white.opacity(0.05)))
        .overlay(Pilula().strokeBorder(Tema.borda))
    }

    private func procurar(paraTras: Bool) {
        guard let web = viva?.web, !busca.isEmpty else { return }
        let c = WKFindConfiguration()
        c.backwards = paraTras
        c.wraps = true
        web.find(busca, configuration: c) { achou in
            MainActor.assumeIsolated {
                if !achou.matchFound { s.aviso = AvisoNav(texto: "Nada encontrado para “\(busca)”", arquivo: nil) }
            }
        }
    }

    private func menuDaPagina() -> [ItemMenu] {
        guard let aba, let viva else { return menuDoNavegador() }
        var permissoes: [ItemMenu] = []
        if let site = viva.url?.host, PermissoesNav.tem(site) {
            permissoes = [.acao("Esquecer as permissões de \(site)", icone: "hand.raised.slash",
                                detalhe: "câmera, microfone, localização: pergunta de novo") {
                PermissoesNav.esquecer(site)
                viva.web.reload()
            }]
        }
        return permissoes + [
            .acao("Copiar endereço", icone: "link", detalhe: "⇧⌘C") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viva.url?.absoluteString ?? aba.url, forType: .string)
            },
            .acao("Buscar na página", icone: "magnifyingglass", detalhe: "⌘F") { s.buscando = true },
            .acao(aba.fixada ? "Desafixar a aba" : "Fixar a aba", icone: aba.fixada ? "pin.slash" : "pin") { s.alternarFixada(aba.id) },
            .divisor,
            .acao("Abrir no navegador padrão", icone: "arrow.up.forward.app") {
                if let u = viva.url { NSWorkspace.shared.open(u) }
            },
            .divisor,
            .acao("Preencher senha…", icone: "key", detalhe: "Senhas do macOS, no campo em foco da página · ⇧⌘P") {
                s.preencherSenha(viva.web)
            },
            .acao("Abrir o app Senhas", icone: "arrow.up.forward.app") { SenhasNav.abrirAppSenhas() },
            .divisor,
        ] + menuDoNavegador()
    }

    /// O que vale para o navegador inteiro: histórico e sugestões.
    private func menuDoNavegador() -> [ItemMenu] {
        let paginas = HistoricoNav.shared.visitas.count
        return [
            .acao("Guardar histórico", icone: "clock.arrow.circlepath",
                  detalhe: "só neste Mac; é dele que saem as sugestões do campo", marcado: HistoricoNav.ligado) {
                HistoricoNav.ligado.toggle()
            },
            .acao("Sugerir buscas ao digitar", icone: "magnifyingglass",
                  detalhe: "manda ao Google o texto que não casa com nada já visitado", marcado: BuscasSugeridas.ligado) {
                BuscasSugeridas.ligado.toggle()
            },
            .acao("Limpar histórico…", icone: "trash",
                  detalhe: paginas == 0 ? "vazio" : "\(paginas) página\(paginas == 1 ? "" : "s")",
                  destrutivo: true, desabilitado: paginas == 0) {
                let a = NSAlert()
                a.messageText = "Limpar o histórico do navegador?"
                a.informativeText = "As \(paginas) páginas guardadas somem e o campo de endereço deixa de completar até você navegar de novo. Abas, logins e cookies não mudam."
                a.addButton(withTitle: "Limpar")
                a.addButton(withTitle: "Cancelar")
                if a.runModal() == .alertFirstButtonReturn {
                    HistoricoNav.shared.limpar()
                    s.aviso = AvisoNav(texto: "Histórico limpo", arquivo: nil)
                }
            },
        ]
    }

    /// Traz do Arc as páginas visitadas (endereço, título, quantas vezes, quando). Só leitura
    /// no Arc; fica neste Mac, no histórico do navegador do Crew.
    private func importarHistoricoDoArc() {
        let a = NSAlert()
        a.messageText = "Importar o histórico do Arc?"
        a.informativeText = "O Crew lê as páginas que você visitou no Arc (as \(HistoricoRegras.limite) mais recentes) e guarda no histórico dele, neste Mac. É delas que o campo de endereço e a busca tiram as sugestões. Nada muda no Arc, e \"Limpar histórico…\" apaga tudo depois."
        a.addButton(withTitle: "Importar")
        a.addButton(withTitle: "Cancelar")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let limite = HistoricoRegras.limite
        Task {
            let lidas = await Task.detached { ArcLeitor.historico(limite: limite) }.value
            let novas = HistoricoNav.shared.importar(lidas)
            s.aviso = AvisoNav(texto: lidas.isEmpty ? "Não achei histórico do Arc neste Mac"
                               : "Histórico do Arc: \(novas) páginas novas", arquivo: nil)
        }
    }

    /// Sem a coluna: as abas e os espaços cabem num menu.
    private func menuAbas() -> [ItemMenu] {
        var itens: [ItemMenu] = [.acao("Nova aba", icone: "plus", detalhe: "⌘T") {
            s.novaAba(espacoId)
        }]
        if let e = s.espaco(espacoId), !e.abas.isEmpty {
            itens.append(.divisor)
            itens += e.abas.map { a in
                .acao(a.titulo, icone: a.fixada ? "pin.fill" : "globe", marcado: a.id == e.ativa) { s.ativar(a.id) }
            }
        }
        itens += [.divisor, .acao("Importar do Arc…", icone: "square.and.arrow.down") { s.importandoArc = true },
                  .acao("Importar o histórico do Arc…", icone: "clock.arrow.circlepath",
                        detalhe: "para o campo e a busca sugerirem seus sites desde já") { importarHistoricoDoArc() }]
        // O navegador de uma sessão é só dela; o da janela alcança o Geral e os espaços de
        // projeto guardados de antes (os avulsos das sessões não entram).
        let outros = s.espacos.filter { !$0.daSessao }
        if !espacoId.hasPrefix(NavegadorServico.prefixoSessao), outros.count > 1 {
            itens += [.divisor, .titulo("Espaços")]
            itens += outros.map { e in
                .acao(e.nome, ponto: Color(hex: e.cor), marcado: e.id == espacoId) { espacoId = e.id }
            }
        }
        return itens
    }
}

private struct BotoesDeNavegar: View {
    @ObservedObject var viva: AbaViva

    var body: some View {
        HStack(spacing: 0) {
            BotaoIcone(icone: "chevron.left", ajuda: "Voltar (⌘[)") { viva.web.goBack() }
                .disabled(!viva.podeVoltar).opacity(viva.podeVoltar ? 1 : 0.35)
            BotaoIcone(icone: "chevron.right", ajuda: "Avançar (⌘])") { viva.web.goForward() }
                .disabled(!viva.podeAvancar).opacity(viva.podeAvancar ? 1 : 0.35)
            BotaoIcone(icone: viva.carregando ? "xmark" : "arrow.clockwise",
                       ajuda: viva.carregando ? "Parar" : "Recarregar (⌘R)") {
                if viva.carregando { viva.web.stopLoading() } else { viva.web.reload() }
            }
        }
    }
}

// MARK: - Coluna de abas

/// As abas lado a lado, como no Safari: dividem a largura por igual; fixadas à esquerda, só
/// com o ícone. Muitas abas: cada uma tem um mínimo e a faixa rola para o lado.
private struct FaixaAbas: View {
    @Binding var espacoId: String
    @ObservedObject private var s = NavegadorServico.shared

    private var espaco: EspacoNav? { s.espaco(espacoId) }

    var body: some View {
        let abas = espaco?.abas ?? []
        let fixadas = abas.filter(\.fixada), soltas = abas.filter { !$0.fixada }
        GeometryReader { geo in
            let livre = geo.size.width - 16 - CGFloat(fixadas.count) * 38
            let largura = soltas.isEmpty ? 0 : max(110, (livre - CGFloat(soltas.count - 1) * 2) / CGFloat(soltas.count))
            ScrollViewReader { rolagem in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(fixadas) { aba($0, largura: 36) }
                        ForEach(soltas) { aba($0, largura: largura) }
                    }
                    .padding(.horizontal, 8)
                }
                .onChange(of: espaco?.ativa) { _, id in
                    if let id { withAnimation(.easeOut(duration: 0.15)) { rolagem.scrollTo(id) } }
                }
            }
        }
        .frame(height: 34)
    }

    private func aba(_ a: AbaNav, largura: CGFloat) -> some View {
        AbaDaFaixa(aba: a, ativa: a.id == espaco?.ativa, aoLado: a.id == espaco?.lado, carregada: s.estaViva(a.id),
                   abrir: { s.ativar(a.id) }, fechar: { s.fechar(a.id) })
            .frame(width: largura)
            .id(a.id)
            .menuContexto {
                [
                    .acao(a.fixada ? "Desafixar" : "Fixar", icone: a.fixada ? "pin.slash" : "pin") { s.alternarFixada(a.id) },
                    .acao(a.id == espaco?.lado ? "Tirar do lado" : "Abrir ao lado", icone: "rectangle.split.2x1") { s.alternarLado(a.id) },
                    .acao("Mover para a esquerda", icone: "arrow.left") { s.mover(a.id, passo: -1) },
                    .acao("Mover para a direita", icone: "arrow.right") { s.mover(a.id, passo: 1) },
                    .acao("Copiar endereço", icone: "link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(a.url, forType: .string)
                    },
                    .divisor,
                    .acao(a.fixada ? "Descarregar" : "Fechar a aba", icone: "xmark", destrutivo: !a.fixada) { s.fechar(a.id) },
                ]
            }
    }
}

/// Uma aba na faixa: ícone e título no meio; o X aparece à esquerda com o mouse em cima.
private struct AbaDaFaixa: View {
    let aba: AbaNav
    let ativa: Bool
    let aoLado: Bool
    let carregada: Bool
    let abrir: () -> Void
    let fechar: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: abrir) {
            HStack(spacing: 6) {
                Favicon(url: aba.url)
                    .opacity(carregada ? 1 : 0.5)
                if !aba.fixada {
                    Text(aba.titulo)
                        .font(.system(size: 12, weight: ativa ? .medium : .regular))
                        .foregroundStyle(ativa ? Tema.texto : Tema.texto2)
                        .lineLimit(1)
                    if aoLado {
                        Image(systemName: "rectangle.split.2x1").font(.system(size: 9.5)).foregroundStyle(Tema.texto3)
                    }
                }
            }
            .padding(.horizontal, aba.fixada ? 0 : 26)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ativa ? Color.white.opacity(0.1) : hover ? Tema.hover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            if hover, !aba.fixada {
                BotaoIcone(icone: "xmark", ajuda: "Fechar a aba (⌘W)", lado: 20, acao: fechar)
                    .padding(.leading, 4)
            }
        }
        .frame(height: 34)
        .onHover { hover = $0 }
        .help(aba.fixada ? "\(aba.titulo) — \(aba.url)" : aba.url)
    }
}

/// O ícone do site; enquanto não vem (ou se não existe), um globo.
struct Favicon: View {
    let url: String
    @State private var imagem: NSImage?

    private var hospedeiro: String? { URL(string: url)?.host }

    var body: some View {
        Group {
            if let imagem {
                Image(nsImage: imagem).resizable().interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(Tema.texto3)
            }
        }
        .frame(width: 15, height: 15)
        .task(id: hospedeiro) {
            imagem = nil
            guard let hospedeiro, !CaptureTool.ativo else { return }
            imagem = await Favicons.de(hospedeiro)
        }
    }
}

import SwiftUI

// Página do Vídeo nos Ajustes do Crew: o motor (instalar, tamanho, remover), criar um vídeo
// descrevendo o que se quer, os projetos (prévia, sessão, renderizar) e os vídeos prontos.

struct VideoCentral: View {
    private let s = VideoServico.shared
    @State private var nomeNovo = ""
    @State private var pedidoNovo = ""
    @State private var confirmandoRemover = false
    @State private var escolhida: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            motor
            if s.instalado {
                legendas
                novo
                if let r = s.render { renderEmCurso(r) }
                projetos
                prontos
            }
            if let a = s.aviso, !(s.instalado == false && !a.erro) || s.aviso?.erro == true {
                linhaAviso(a)
            }
        }
        .onAppear { s.atualizar(); s.conferirFala() }
    }

    // MARK: Legendas pela fala

    private var legendas: some View {
        Secao("Legendas pela fala", "Ao editar uma gravação, o Crew transcreve o que você diz neste Mac (nada sai dele) e a legenda entra no vídeo com o tempo de cada palavra. Idioma: o do ditado (\(s.idiomaDaFala)), em Ajustes › Voz.") {
            HStack(spacing: 10) {
                switch s.fala {
                case .pronto?:
                    Image(systemName: "checkmark.seal.fill").foregroundColor(Color(hex: "#34D399"))
                    Text("Pronto: o modelo de fala de \(s.idiomaDaFala) está neste Mac.").font(.system(size: 12))
                case .faltaModelo?:
                    Image(systemName: "arrow.down.circle").foregroundColor(.orange)
                    if let f = s.baixandoFala {
                        ProgressView(value: f).frame(width: 140)
                        Text("Baixando o modelo de fala… \(Int(f * 100)) %").font(.system(size: 12)).monospacedDigit()
                    } else {
                        Text("Falta o modelo de fala de \(s.idiomaDaFala): sem ele o vídeo sai sem legenda.").font(.system(size: 12))
                        Spacer(minLength: 0)
                        Button("Baixar o modelo") { s.baixarModeloDeFala() }.controlSize(.small)
                            .help("Baixa da Apple, pelo macOS, o modelo que transcreve a fala neste Mac. Só o modelo vem da rede; o áudio nunca sai daqui.")
                    }
                case .semSuporte(let motivo)?:
                    Image(systemName: "exclamationmark.triangle").foregroundColor(.orange)
                    Text(motivo).font(.system(size: 12))
                case nil:
                    ProgressView().controlSize(.small)
                    Text("Conferindo…").font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let nome = s.transcrevendo {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Transcrevendo a fala de \(nome)…").font(.system(size: 11)).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: Motor

    private var motor: some View {
        Secao("Motor de vídeo", "O Remotion roda como um programa à parte (Node.js), só enquanto você usa: nada fica ligado em segundo plano.") {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: s.instalado ? "checkmark.seal.fill" : "shippingbox")
                    .font(.system(size: 20))
                    .foregroundColor(s.instalado ? Color(hex: "#34D399") : .secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 3) {
                    Text(s.instalado ? "Remotion \(s.versaoInstalada ?? "") instalado" : "Motor ainda não instalado")
                        .font(.system(size: 13, weight: .medium))
                    Text(s.instalado
                         ? "Ocupa \(Self.tamanho(s.tamanhoMotor)) em disco. Os vídeos prontos vão para Filmes › Crew."
                         : "Instalar baixa o Remotion e um navegador sem janela que desenha os quadros (cerca de 400 MB no total). Precisa de internet só agora.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            if let linha = s.instalando {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(linha.isEmpty ? "Instalando…" : linha).font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    Button("Cancelar") { s.cancelarInstalacao() }.controlSize(.small)
                }
            } else if !s.instalado {
                if let motivo = MotorRemotion.motivoIndisponivel {
                    Text(motivo).font(.system(size: 11)).foregroundColor(.orange)
                } else {
                    Button("Instalar o motor de vídeo") { s.instalar() }.buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Abrir a pasta dos projetos") { s.mostrarNoFinder(MotorRemotion.videos) }
                    Button("Abrir os vídeos prontos") { NSWorkspace.shared.open(MotorRemotion.saidas) }
                    Spacer(minLength: 0)
                    if confirmandoRemover {
                        Text("Seus projetos e vídeos ficam.").font(.system(size: 11)).foregroundColor(.secondary)
                        Button("Remover") { s.removerMotor(); confirmandoRemover = false }
                        Button("Cancelar") { confirmandoRemover = false }
                    } else {
                        Button("Remover o motor…") { confirmandoRemover = true }.disabled(s.render != nil)
                    }
                }
                .controlSize(.small)
            }
            Text("Licença do Remotion: grátis para uso pessoal e para empresas de até 3 pessoas. Acima disso, exige licença paga (remotion.dev/license).")
                .font(.system(size: 10.5)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Novo vídeo

    private var novo: some View {
        Secao("Novo vídeo", "Dê um nome e descreva o que quer. O Crew cria o projeto e abre uma sessão do Claude Code que escreve o vídeo; você acompanha pela prévia.") {
            TextField("Nome do vídeo (ex.: lançamento do Crew)", text: $nomeNovo)
                .textFieldStyle(.roundedBorder)
            TextField("O que o vídeo mostra? (formato, duração, textos, tom)", text: $pedidoNovo, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button("Criar com o Claude Code") { criar(comSessao: true) }
                    .buttonStyle(.borderedProminent)
                    .disabled(MotorRemotion.nomeDePasta(nomeNovo).isEmpty || pedidoNovo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Criar só o projeto") { criar(comSessao: false) }
                    .disabled(MotorRemotion.nomeDePasta(nomeNovo).isEmpty)
            }
        }
    }

    private func criar(comSessao: Bool) {
        switch s.criar(nome: nomeNovo) {
        case .success(let p):
            if comSessao {
                s.abrirSessao(p, pedido: "Crie este vídeo neste projeto do Remotion (leia o CLAUDE.md da pasta do motor antes): \(pedidoNovo.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            nomeNovo = ""
            pedidoNovo = ""
            s.aviso = .init(texto: comSessao ? "Projeto \(p.nome) criado. A sessão abriu no app do Crew." : "Projeto \(p.nome) criado com um vídeo de partida.", erro: false)
        case .failure(let f):
            s.aviso = .init(texto: f.texto, erro: true)
        }
    }

    // MARK: Renderização em curso

    private func renderEmCurso(_ r: VideoServico.Render) -> some View {
        Secao("Renderizando", nil) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(r.projeto) · \(r.composicao)").font(.system(size: 12, weight: .medium))
                    ProgressView(value: r.fracao)
                    Text(r.total > 0 ? "\(r.fase): \(r.feitos) de \(r.total) quadros" : r.fase + "…")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Button("Cancelar") { s.cancelarRender() }.controlSize(.small)
            }
        }
    }

    // MARK: Projetos

    private var projetos: some View {
        Secao("Projetos", s.projetos.isEmpty ? nil : "Cada projeto pode ter vários vídeos (composições): paisagem, vertical, versões.") {
            if s.projetos.isEmpty {
                Text("Nenhum projeto ainda. Crie o primeiro acima.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            ForEach(s.projetos) { p in
                linhaProjeto(p)
                if p.id != s.projetos.last?.id { Divider() }
            }
        }
    }

    private func linhaProjeto(_ p: ProjetoVideo) -> some View {
        let ids = s.composicoes[p.nome]
        let atual = escolhida[p.nome] ?? ids?.first
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack").foregroundColor(.secondary)
                Text(p.nome).font(.system(size: 13, weight: .medium))
                Text(Self.quando(p.modificado)).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer(minLength: 0)
                if s.previa?.projeto == p.nome {
                    Text(s.previa?.pronta == true ? "prévia aberta" : "abrindo a prévia…")
                        .font(.system(size: 10.5)).foregroundColor(.accentColor)
                }
            }
            HStack(spacing: 8) {
                if s.previa?.projeto == p.nome {
                    Button("Fechar prévia") { s.fecharPrevia() }
                } else {
                    Button("Abrir prévia") { s.abrirPrevia(p.nome) }
                }
                Button("Editar com o Claude Code") { s.abrirSessao(p) }
                Spacer(minLength: 0)
                if s.lendoComposicoes.contains(p.nome) {
                    ProgressView().controlSize(.small)
                    Text("lendo o projeto…").font(.system(size: 11)).foregroundColor(.secondary)
                } else if let ids, !ids.isEmpty {
                    if ids.count > 1 {
                        Picker("", selection: Binding(get: { atual ?? ids[0] }, set: { escolhida[p.nome] = $0 })) {
                            ForEach(ids, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden().frame(maxWidth: 150)
                    }
                    Button("Renderizar \(ids.count > 1 ? "" : ids[0])") {
                        if let c = atual, case .failure(let f) = s.renderizar(projeto: p.nome, composicao: c) {
                            s.aviso = .init(texto: f.texto, erro: true)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(s.render != nil)
                } else {
                    Button(ids == nil ? "Ler vídeos do projeto" : "Ler de novo") { s.carregarComposicoes(p.nome) }
                }
                Menu {
                    Button("Mostrar no Finder") { s.mostrarNoFinder(p.pasta) }
                    Button("Ler os vídeos do projeto de novo") { s.carregarComposicoes(p.nome) }
                    if VideoServico.gravacaoDe(p) != nil {
                        Button("Refazer as legendas pela fala") { s.refazerLegendas(p) }.disabled(s.transcrevendo != nil)
                    }
                    Divider()
                    Button("Mover para o Lixo", role: .destructive) { s.apagarProjeto(p) }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize()
            }
            .controlSize(.small)
        }
        .onAppear { if s.composicoes[p.nome] == nil { s.carregarComposicoes(p.nome) } }
    }

    // MARK: Prontos

    private var prontos: some View {
        Secao("Vídeos prontos", s.prontos.isEmpty ? nil : "Em Filmes › Crew. Arraste um vídeo daqui para qualquer app.") {
            if s.prontos.isEmpty {
                Text("O que você renderizar aparece aqui.").font(.system(size: 12)).foregroundColor(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 12)], alignment: .leading, spacing: 12) {
                ForEach(s.prontos.prefix(12)) { v in cartao(v) }
            }
        }
    }

    private func cartao(_ v: VideoPronto) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.85))
                if let img = s.miniaturas[v.id] {
                    Image(nsImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: "film").font(.system(size: 22)).foregroundColor(.white.opacity(0.35))
                }
                Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(.white.opacity(0.9), .black.opacity(0.35))
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture { NSWorkspace.shared.open(v.url) }
            .onDrag { NSItemProvider(contentsOf: v.url) ?? NSItemProvider() }
            Text(v.nome).font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text([s.duracoes[v.id].map(Self.duracao), Self.tamanho(v.bytes), Self.quando(v.data)].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1)
        }
        .contextMenu {
            Button("Abrir") { NSWorkspace.shared.open(v.url) }
            Button("Mostrar no Finder") { s.mostrarNoFinder(v.url) }
            Button("Copiar o caminho") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(v.url.path, forType: .string)
            }
            Divider()
            Button("Mover para o Lixo", role: .destructive) { s.apagarVideo(v) }
        }
    }

    // MARK: Peças

    private func linhaAviso(_ a: VideoServico.Aviso) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: a.erro ? "exclamationmark.triangle.fill" : "checkmark.circle")
                .foregroundColor(a.erro ? .orange : .secondary)
            Text(a.texto).font(.system(size: a.erro ? 11 : 12, design: a.erro ? .monospaced : .default))
                .foregroundColor(.secondary).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { s.aviso = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).controlSize(.small)
        }
    }

    private static func tamanho(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func duracao(_ segundos: Double) -> String {
        let t = Int(segundos.rounded())
        return t >= 60 ? "\(t / 60) min \(t % 60) s" : "\(t) s"
    }

    private static func quando(_ data: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.unitsStyle = .short
        return f.localizedString(for: data, relativeTo: Date())
    }
}

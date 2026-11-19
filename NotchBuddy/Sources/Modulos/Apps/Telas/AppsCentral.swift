import AppKit
import SwiftUI

// Página do módulo Apps na Central: apagados recentemente (da vigia), desinstalador (lista de
// apps → sobras do escolhido → confirmação), sobras de apps já apagados e o Acesso Total ao Disco.

struct AppsCentral: View {
    private let s = AppsServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let r = s.ultimo { resultado(r) }
            if let c = s.confirmacao {
                confirmacao(c)
            } else {
                if !s.apagados.isEmpty { apagados }
                desinstalador
                orfas
            }
            acessoTotal
        }
        .onAppear { s.paginaAbriu() }
    }

    // MARK: Apagados recentemente

    private var apagados: some View {
        Secao("Apagados recentemente",
              "Apps que saíram de /Applications nos últimos 7 dias e deixaram pastas para trás. Casamento por bundle id vem marcado; só por nome, desmarcado.") {
            if s.lendoApagados {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Conferindo as sobras…").font(.system(size: 12)).foregroundColor(.secondary) }
            }
            ForEach(s.apagados) { a in
                let lista = s.sobrasApagado[a.id] ?? []
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(a.nome).font(.system(size: 12.5, weight: .semibold))
                        Text("apagado \(FormatoApps.ha(a.quando))").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Text(FormatoApps.bytes(lista.reduce(0) { $0 + ($1.bytes ?? 0) }))
                            .font(.system(size: 11)).foregroundColor(.secondary).monospacedDigit()
                    }
                    ForEach(lista) { linha($0) }
                    HStack {
                        Button("Esquecer") { s.esquecer(a.id) }.controlSize(.small)
                        Spacer()
                        let m = s.marcadas(.apagado(a.id))
                        Button("Mover \(m.count) para a Lixeira…") { s.prepararConfirmacao(.apagado(a.id)) }
                            .controlSize(.small).disabled(m.isEmpty || s.preparando || s.removendo)
                    }
                }
                if a.id != s.apagados.last?.id { Divider() }
            }
        }
    }

    // MARK: Desinstalador

    private var desinstalador: some View {
        Secao("Desinstalar",
              "Apps de /Applications e ~/Applications (sem os do sistema e sem o Crew). Escolha um para ver o que sai com ele. Se estiver aberto, o Crew pede para fechar (nunca força); se não fechar, nada sai.") {
            HStack(spacing: 8) {
                TextField("Filtrar", text: Binding(get: { s.filtro }, set: { s.filtro = $0 }))
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Picker("", selection: Binding(get: { s.ordem }, set: { s.ordem = $0 })) {
                    ForEach(AppsServico.Ordem.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 250)
                Spacer()
                if s.estadoLista == .lendo { ProgressView().controlSize(.small) }
                Text("\(s.apps.count) apps").font(.system(size: 11)).foregroundColor(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(s.appsVisiveis) { linhaApp($0) }
                }
            }
            .frame(height: 260)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let a = s.escolhido { sobrasDoApp(a) }
        }
    }

    private func linhaApp(_ a: AppInstalado) -> some View {
        let sel = s.escolhido?.id == a.id
        return Button {
            s.escolher(sel ? nil : a)
        } label: {
            HStack(spacing: 8) {
                IconeApp(caminho: a.caminho)
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.nome).font(.system(size: 12.5)).lineLimit(1)
                    Text((a.caminho as NSString).abbreviatingWithTildeInPath).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Text(FormatoApps.data(a.ultimoUso)).font(.system(size: 11)).foregroundColor(.secondary).frame(width: 90, alignment: .trailing)
                Text(a.bytes.map(FormatoApps.bytes) ?? "—").font(.system(size: 11.5)).monospacedDigit().frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(sel ? Color.accentColor.opacity(0.18) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sobrasDoApp(_ a: AppInstalado) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("O que sai com \(a.nome)").font(.system(size: 12.5, weight: .semibold))
                Spacer()
                if s.lendoSobras { ProgressView().controlSize(.small) }
            }
            ForEach(s.sobras) { linha($0) }
            if !s.lendoSobras {
                if s.pacoteBloqueado {
                    Text("O Crew não tem permissão para mover \(a.nome) (instalado pelo administrador ou protegido pelo macOS) e não pede senha nem usa helper: arraste o app para a Lixeira pelo Finder — com o aviso ligado, as sobras aparecem em \"Apagados recentemente\".")
                        .font(.system(size: 11)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                let m = s.marcadas(.app(a))
                HStack {
                    Text("Marcado: \(m.count) · \(FormatoApps.bytes(m.reduce(0) { $0 + ($1.bytes ?? 0) }))")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Spacer()
                    if s.preparando { ProgressView().controlSize(.small) }
                    Button("Desinstalar…") { s.prepararConfirmacao(.app(a)) }
                        .disabled(s.pacoteBloqueado || s.sobras.isEmpty || s.preparando || s.removendo)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Órfãs

    private var orfas: some View {
        Secao("Sobras de apps já apagados",
              "Pastas com nome de bundle id (Application Support, Contêineres, HTTPStorages, Estado salvo) de apps que não estão mais instalados e sem mexer há \(PoliticaOrfas.diasParado)+ dias. Na dúvida (id de serviço da Apple, dono incerto, helper de um app instalado), não aparece. Nada vem marcado: é dado de app, não cache.") {
            HStack(spacing: 10) {
                switch s.estadoOrfas {
                case .nunca: Text("Ainda não procurou.").font(.system(size: 12)).foregroundColor(.secondary)
                case .lendo:
                    ProgressView().controlSize(.small)
                    Text("Procurando…").font(.system(size: 12)).foregroundColor(.secondary)
                case .pronto(let q):
                    Text("Procurado \(FormatoApps.ha(q)) · \(s.orfas.count) \(s.orfas.count == 1 ? "item" : "itens") · \(FormatoApps.bytes(s.orfas.reduce(0) { $0 + ($1.bytes ?? 0) }))")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button(s.estadoOrfas == .nunca ? "Procurar" : "Procurar de novo") { s.procurarOrfas() }
                    .disabled(s.estadoOrfas == .lendo)
            }
            ForEach(s.orfas) { linha($0) }
            if !s.orfas.isEmpty {
                Divider()
                let m = s.marcadas(.orfas)
                HStack {
                    Text("Marcado: \(m.count) · \(FormatoApps.bytes(m.reduce(0) { $0 + ($1.bytes ?? 0) }))")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Spacer()
                    Button("Mover para a Lixeira…") { s.prepararConfirmacao(.orfas) }
                        .disabled(m.isEmpty || s.preparando || s.removendo)
                }
            }
        }
    }

    // MARK: Linha de sobra

    private func linha(_ x: Sobra) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { s.marcados.contains(x.id) }, set: { _ in s.alternar(x.id) }))
                .toggleStyle(.checkbox).labelsHidden()
                .disabled(x.categoria == .app)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(x.dono ?? x.nome).font(.system(size: 12)).lineLimit(1)
                    etiqueta(x.categoria.rawValue, .secondary)
                    if x.motivo == .nome { etiqueta("só pelo nome — conferir", .orange) }
                    if x.precisaAdmin { etiqueta("sem permissão — vai ficar", .red) }
                }
                Text((x.caminho as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(x.bytes.map(FormatoApps.bytes) ?? "—").font(.system(size: 12)).monospacedDigit()
        }
        .help(x.caminho)
    }

    private func etiqueta(_ t: String, _ cor: Color) -> some View {
        Text(t).font(.system(size: 9.5, weight: .medium))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(cor.opacity(0.15)).foregroundColor(cor)
            .clipShape(Capsule())
    }

    // MARK: Confirmação

    private func confirmacao(_ c: AppsServico.Confirmacao) -> some View {
        Secao("Confirmar: \(c.titulo)",
              "Conferido de novo agora; o que mudou saiu da lista. Vai tudo para a Lixeira (dá para pôr de volta até esvaziá-la).") {
            if c.appAberto, case .app(let a) = c.contexto {
                Label("\(a.nome) está aberto: o Crew pede para ele fechar e espera até 3 s. Se não fechar, nada sai.", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11.5)).foregroundColor(.orange)
            }
            ForEach(c.itens) { x in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(x.categoria == .app ? "App" : x.categoria.rawValue).font(.system(size: 12))
                            if x.precisaAdmin { etiqueta("sem permissão — deve ficar", .red) }
                        }
                        Text((x.caminho as NSString).abbreviatingWithTildeInPath)
                            .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(2).truncationMode(.middle)
                    }
                    Spacer()
                    Text(x.bytes.map(FormatoApps.bytes) ?? "—").font(.system(size: 12)).monospacedDigit()
                }
            }
            if !s.foraNaRevalidacao.isEmpty {
                Text("Saíram da lista: " + s.foraNaRevalidacao.map { "\($0.nome) (\($0.motivo))" }.joined(separator: ", "))
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
            Divider()
            HStack {
                Text("Total: \(c.itens.count) \(c.itens.count == 1 ? "item" : "itens") · \(FormatoApps.bytes(c.total))")
                    .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                Spacer()
                if s.removendo {
                    ProgressView().controlSize(.small)
                    if let e = s.etapa { Text(e).font(.system(size: 11)).foregroundColor(.secondary) }
                }
                Button("Cancelar") { s.cancelarConfirmacao() }.disabled(s.removendo)
                Button("Mover para a Lixeira") { s.confirmar() }
                    .keyboardShortcut(.defaultAction).disabled(s.removendo)
            }
        }
    }

    // MARK: Resultado

    private func resultado(_ r: ResultadoRemocao) -> some View {
        Secao("Última remoção: \(r.titulo)", FormatoApps.ha(r.quando)) {
            HStack {
                Text("Para a Lixeira: \(r.movidos.count) \(r.movidos.count == 1 ? "item" : "itens") · \(FormatoApps.bytes(r.bytes))")
                    .font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                Spacer()
                Button("Ok") { s.ultimo = nil }.controlSize(.small)
            }
            if !r.movidos.isEmpty {
                Text("Mover para a Lixeira não libera espaço: ele volta quando a Lixeira for esvaziada.")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            ForEach(Array(r.ficaram.enumerated()), id: \.offset) { _, f in
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ficou: \((f.caminho as NSString).abbreviatingWithTildeInPath)").font(.system(size: 11.5))
                    Text(f.motivo).font(.system(size: 11)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Acesso Total ao Disco

    private var acessoTotal: some View {
        Secao("Acesso Total ao Disco", nil) {
            HStack(spacing: 8) {
                Image(systemName: s.acesso == .total ? "checkmark.circle.fill" : "lock")
                    .foregroundColor(s.acesso == .total ? .green : .secondary)
                Text(s.acesso == .total ? "Ligado para o Crew: os contêineres dos apps entram na busca."
                     : "Desligado: Contêineres e Contêineres de grupo (~/Library/Containers, Group Containers) ficam de fora — o macOS pediria permissão. Apps da App Store guardam quase tudo lá.")
                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            if s.acesso != .total {
                Button("Abrir Ajustes do Sistema › Acesso Total ao Disco") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }
}

/// Ícone do app (lido uma vez por caminho).
private struct IconeApp: View {
    let caminho: String
    @MainActor private static var cache: [String: NSImage] = [:]

    var body: some View {
        Image(nsImage: Self.icone(caminho)).resizable().frame(width: 20, height: 20)
    }

    @MainActor private static func icone(_ c: String) -> NSImage {
        if let i = cache[c] { return i }
        let i = NSWorkspace.shared.icon(forFile: c)
        cache[c] = i
        return i
    }
}

struct AppsAjustes: View {
    @State private var vigia = VigiaApps.ligada

    var body: some View {
        Toggle("Avisar na ilha quando um app for apagado", isOn: $vigia)
            .onChange(of: vigia) { _, v in VigiaApps.ligada = v }
        Text("Enquanto ligado, o macOS avisa o Crew quando algo muda em /Applications ou ~/Applications (evento, sem timer; nada roda se as pastas não mudam). Quando um app some, o Crew espera 10 s — se o mesmo app voltar (atualização), não avisa. Se sumiu mesmo e deixou pastas, aparece na ilha e em \"Apagados recentemente\".")
            .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

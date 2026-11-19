import AppKit
import SwiftUI

// Página do Disco na Central: espaço, lista do que dá para limpar (por grupo, com marcação),
// confirmação com o que sai e o total, resultado da última limpeza e o Acesso Total ao Disco.

struct DiscoCentral: View {
    private let s = DiscoServico.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Secao("Espaço", nil) {
                BarraDisco(volume: s.volume, trilho: Color.primary.opacity(0.08), altura: 8)
                HStack(spacing: 22) {
                    par("Livre", s.volume.map { DiscoFormato.bytes($0.livre) } ?? "—")
                    par("Em uso", s.volume.map { DiscoFormato.bytes($0.usado) } ?? "—")
                    par("Total", s.volume.map { DiscoFormato.bytes($0.total) } ?? "—")
                }
            }

            if let r = s.ultimo { resultado(r) }

            if let lista = s.confirmacao {
                confirmacao(lista)
            } else {
                recuperavel
            }

            ProjetosCentral()
            SimuladoresCentral()
            ArquivosGrandesCentral()
            DuplicadosCentral()

            acessoTotal
        }
        .onAppear {
            s.assinar("central")
            SimuladoresServico.shared.aoAparecer()
        }
        .onDisappear { s.soltar("central") }
    }

    // MARK: Lista

    private var recuperavel: some View {
        Secao("Recuperável com segurança",
              "Caches que os apps e as ferramentas refazem sozinhos. Vai tudo para a Lixeira (dá para desfazer até esvaziá-la). Os marcados por padrão são os classificados como seguros; os \"conferir\" se refazem, mas não sozinhos ou não rápido.") {
            HStack(spacing: 10) {
                switch s.estado {
                case .nunca:
                    Text("Ainda não procurou.").font(.system(size: 12)).foregroundColor(.secondary)
                case .varrendo(let etapa):
                    ProgressView().controlSize(.small)
                    Text(etapa).font(.system(size: 12)).foregroundColor(.secondary)
                case .pronto(let q):
                    Text("Procurado \(DiscoFormato.ha(q)) · \(DiscoFormato.bytes(s.recuperavel)) seguros")
                        .font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Button(s.estado == .nunca ? "Procurar" : "Procurar de novo") { s.procurar() }
                    .disabled(s.varrendo || s.movendo)
            }

            ForEach(GrupoLimpeza.allCases, id: \.self) { g in
                let doGrupo = s.itens.filter { $0.grupo == g }
                if !doGrupo.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(g.rawValue).font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text(DiscoFormato.bytes(doGrupo.reduce(0) { $0 + $1.bytes }))
                                .font(.system(size: 11)).foregroundColor(.secondary).monospacedDigit()
                        }
                        .padding(.top, 4)
                        ForEach(doGrupo) { linha($0) }
                    }
                }
            }

            if case .pronto = s.estado {
                if s.itens.isEmpty {
                    Text("Nada que valha limpar agora.").font(.system(size: 12)).foregroundColor(.secondary)
                } else {
                    Divider()
                    HStack {
                        Text("Selecionado: \(s.selecionados.count) · \(DiscoFormato.bytes(s.totalSelecionado))")
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        Spacer()
                        if s.preparando { ProgressView().controlSize(.small) }
                        Button("Mover para a Lixeira…") { s.prepararConfirmacao() }
                            .disabled(s.selecionados.isEmpty || s.preparando || s.movendo)
                    }
                }
            }
        }
    }

    private func linha(_ i: ItemLimpeza) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(get: { s.selecionados.contains(i.id) }, set: { _ in s.alternar(i.id) }))
                .toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(i.nome).font(.system(size: 12.5))
                    if i.nivel == .conferir {
                        Text("conferir").font(.system(size: 9.5, weight: .medium))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18)).foregroundColor(.orange)
                            .clipShape(Capsule())
                    }
                }
                Text(i.explicacao).font(.system(size: 11)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(DiscoFormato.bytes(i.bytes)).font(.system(size: 12)).monospacedDigit()
        }
        .help(i.caminhos.joined(separator: "\n"))
    }

    // MARK: Confirmação

    private func confirmacao(_ lista: [ItemLimpeza]) -> some View {
        let total = lista.reduce(Int64(0)) { $0 + $1.bytes }
        return Secao("Confirmar: mover para a Lixeira",
                     "Cada item foi conferido de novo agora; o que mudou desde a varredura saiu da lista. Nada é apagado de vez: fica na Lixeira até você esvaziá-la.") {
            ForEach(lista) { i in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(i.nome).font(.system(size: 12))
                        Text(i.caminhos.map { ($0 as NSString).abbreviatingWithTildeInPath }.joined(separator: ", "))
                            .font(.system(size: 10.5)).foregroundColor(.secondary).lineLimit(2).truncationMode(.middle)
                    }
                    Spacer()
                    Text(DiscoFormato.bytes(i.bytes)).font(.system(size: 12)).monospacedDigit()
                }
            }
            if !s.retiradosNaRevalidacao.isEmpty {
                Text("Saíram da lista: " + s.retiradosNaRevalidacao.map(\.nome).joined(separator: ", "))
                    .font(.system(size: 11)).foregroundColor(.orange)
            }
            Divider()
            HStack {
                Text("Total: \(lista.count) \(lista.count == 1 ? "item" : "itens") · \(DiscoFormato.bytes(total))")
                    .font(.system(size: 12.5, weight: .semibold)).monospacedDigit()
                Spacer()
                if s.movendo { ProgressView().controlSize(.small) }
                Button("Cancelar") { s.cancelarConfirmacao() }.disabled(s.movendo)
                Button("Mover para a Lixeira") { s.confirmarMover() }
                    .keyboardShortcut(.defaultAction).disabled(s.movendo)
            }
        }
    }

    // MARK: Resultado

    private func resultado(_ r: ResultadoLimpeza) -> some View {
        Secao("Última limpeza", DiscoFormato.ha(r.quando)) {
            HStack(spacing: 22) {
                par("Movido para a Lixeira", DiscoFormato.bytes(r.bytesMovidos))
                par("Voltou ao disco", r.bytesVoltaram.map(DiscoFormato.bytes) ?? "ainda nada")
            }
            if r.bytesVoltaram == nil {
                Text("Mover para a Lixeira não libera espaço: ele volta quando a Lixeira for esvaziada (Finder › Esvaziar Lixeira).")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            ForEach(r.movidos) { i in
                HStack {
                    Text(i.nome).font(.system(size: 12))
                    Spacer()
                    Text(DiscoFormato.bytes(i.bytes)).font(.system(size: 12)).foregroundColor(.secondary).monospacedDigit()
                }
            }
            ForEach(Array((r.retirados + r.falhas).enumerated()), id: \.offset) { _, f in
                Text("\(f.nome): \(f.motivo)").font(.system(size: 11)).foregroundColor(.orange)
            }
        }
    }

    // MARK: Acesso Total ao Disco

    private var acessoTotal: some View {
        Secao("Acesso Total ao Disco", nil) {
            HStack(spacing: 8) {
                Image(systemName: s.acesso == .total ? "checkmark.circle.fill" : "lock")
                    .foregroundColor(s.acesso == .total ? .green : .secondary)
                Text(s.acesso == .total ? "Ligado para o Crew." : "Desligado: o Crew procura só onde o macOS não pede permissão.")
                    .font(.system(size: 12))
            }
            Text("Sem ele, ficam de fora os caches dentro dos contêineres de apps (~/Library/Containers), os caches de Música/TV/Podcasts, projetos e arquivos em Mesa, Documentos e Downloads, e qualquer pasta que aponte para elas — e o Crew nunca dispara pedidos de permissão. Com ele, a varredura também entra nos contêineres (apps da App Store e do sistema). Os caches de conta, iCloud e chaveiro continuam bloqueados de qualquer jeito.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if s.acesso != .total {
                Button("Abrir Ajustes do Sistema › Acesso Total ao Disco") {
                    if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(u)
                    }
                }
            }
        }
    }

    private func par(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 10.5)).foregroundColor(.secondary)
            Text(v).font(.system(size: 13, weight: .medium)).monospacedDigit()
        }
    }
}

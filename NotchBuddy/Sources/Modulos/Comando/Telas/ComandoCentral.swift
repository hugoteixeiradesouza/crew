import SwiftUI

// A página do Comando nos Ajustes do Crew: o que dá para digitar (com exemplos) e os ajustes
// (atalho, fontes, o que ele aprendeu).

struct ComandoCentral: View {
    @ObservedObject private var s = ComandoServico.shared

    private static let exemplos: [(icone: String, titulo: String, exemplo: String)] = [
        ("app.dashed", "Apps, arquivos e pastas", "safari  ·  contrato 2026  ·  downloads"),
        ("equal.circle", "Contas e unidades", "1.234,56 + 10%  ·  15% de 380  ·  10 km em milhas"),
        ("gear", "Ajustes do Sistema", "bluetooth  ·  telas  ·  privacidade"),
        ("character.bubble", "Tradutor", "traduz bom dia  ·  good morning em português"),
        ("globe", "Navegador do Crew", "github.com  ·  localhost:3000  ·  qualquer busca"),
        ("terminal", "O Crew", "nome da sessão ou do projeto  ·  capturar área  ·  ditar  ·  nota comprar pão"),
        ("sparkles", "Perguntar ao Claude Code", "o que não casar com nada, como item que você escolhe"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("Abrir o Plug") { s.abrir() }
                Text(s.atalhoLigado ? "ou \(s.combinacao.rotulo), de qualquer app" : "o atalho está desligado")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Secao("O que dá para digitar", "↑ ↓ escolhem, Enter faz, ⌘Enter é a segunda ação (mostrar no Finder, abrir no navegador padrão), Esc limpa e fecha.") {
                ForEach(Self.exemplos, id: \.titulo) { e in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: e.icone).frame(width: 18).foregroundColor(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.titulo).font(.system(size: 12, weight: .medium))
                            Text(e.exemplo).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct ComandoAjustes: View {
    @ObservedObject private var s = ComandoServico.shared

    private static let fontes: [(chave: String, titulo: String, detalhe: String)] = [
        ("arquivos", "Arquivos e pastas", "Pelo índice do macOS (o do Spotlight). Só nomes; a consulta só existe com o painel aberto."),
        ("tradutor", "Tradutor", "No aparelho, com os idiomas baixados nos Ajustes do Sistema. Nada é enviado."),
        ("web", "Navegador do Crew", "Endereços, abas abertas e “Pesquisar na web”. A página só abre quando você escolhe."),
        ("perguntar", "Perguntar ao Claude Code", "Abre uma sessão nova com o texto, no último projeto. Nunca sozinho."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Atalho").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(get: { s.atalhoLigado }, set: { s.ligarAtalho($0) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                Text("Abrir o Plug").font(.system(size: 12))
                Button { s.gravandoAtalho ? s.cancelarGravacao() : s.gravarAtalho() } label: {
                    Text(s.gravandoAtalho ? "aperte a combinação…" : s.combinacao.rotulo)
                        .font(s.gravandoAtalho ? .system(size: 11) : .system(size: 12, weight: .medium).monospaced())
                        .foregroundColor(s.gravandoAtalho ? .accentColor : .primary)
                        .padding(.horizontal, 9)
                        .frame(minWidth: 74, minHeight: 22)
                        .background(Color.primary.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: s.gravandoAtalho ? 1.5 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clique e aperte a combinação nova")
                .disabled(!s.atalhoLigado)
                if !s.atalhoEhPadrao {
                    Button("Padrão") { s.definirAtalho(ComandoServico.atalhoPadrao) }
                        .buttonStyle(.link).font(.system(size: 11))
                }
                Spacer(minLength: 0)
            }
            if s.atalhoRecusado {
                Label("não registrou: outro app (ou outro atalho) já usa esta combinação", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5)).foregroundColor(.orange)
            }
            Text("Vale em qualquer app. Clique na combinação e aperte a nova (com ⌃, ⌥ ou ⌘); Esc deixa como estava. Não precisa de Acessibilidade: o macOS só avisa o Crew quando a combinação exata é apertada.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)
            Text("Usar o ⌘ Espaço").font(.system(size: 12, weight: .semibold))
            Text("O ⌘ Espaço é do Spotlight e o Crew não o toma. Para passar para o Crew: em Ajustes do Sistema › Teclado › Atalhos de Teclado… › Spotlight, desmarque “Mostrar busca do Spotlight”. Depois volte aqui, clique na combinação acima e aperte ⌘ Espaço. Para desfazer, marque de novo lá e clique em “Padrão” aqui.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Abrir os ajustes de Teclado") {
                if let u = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") { NSWorkspace.shared.open(u) }
            }
            .controlSize(.small)

            Divider().padding(.vertical, 2)
            Text("O que aparece").font(.system(size: 12, weight: .semibold))
            ForEach(Self.fontes, id: \.chave) { f in
                HStack(alignment: .top, spacing: 8) {
                    Toggle("", isOn: Binding(get: { s.fonteLigada(f.chave) }, set: { s.ligarFonte(f.chave, $0) }))
                        .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    VStack(alignment: .leading, spacing: 1) {
                        Text(f.titulo).font(.system(size: 12))
                        Text(f.detalhe).font(.system(size: 11)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Apps, contas, Ajustes do Sistema e o próprio Crew (sessões, projetos, ações e páginas de ajuste) aparecem sempre.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 2)
            Text("O que ele aprendeu").font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                Text(s.quantoAprendeu == 0 ? "Nada ainda." : "\(s.quantoAprendeu) \(s.quantoAprendeu == 1 ? "escolha guardada" : "escolhas guardadas").")
                    .font(.system(size: 12)).monospacedDigit()
                Button("Esquecer") { s.esquecerAprendizado() }
                    .controlSize(.small).disabled(s.quantoAprendeu == 0)
                Spacer(minLength: 0)
            }
            Text("O que você escolhe sobe na lista, e o mesmo texto volta a trazer a mesma escolha. Fica só nos ajustes deste Mac.")
                .font(.system(size: 11)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear { s.cancelarGravacao() }
    }
}

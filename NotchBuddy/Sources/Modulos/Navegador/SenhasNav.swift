import AppKit
import WebKit

// Senhas da Apple nas páginas do navegador do Crew.
//
// O que existe para app de terceiro (conferido neste Mac, macOS 27.0, nos headers do SDK e
// rodando): o macOS tem um painel de preenchimento ("Preenchimento Automático > Senhas…", do
// app Senhas / Chaves do iCloud) que qualquer app pode abrir sobre um campo de texto. Ele pede
// Touch ID ou a senha do Mac, mostra as senhas guardadas e **digita** a escolhida no campo em
// foco. Num campo nativo o AppKit oferece isso sozinho; num campo de página (WKWebView) o item
// do menu fica apagado, porque o WKWebView não responde ao comando — o painel em si funciona.
// Este arquivo faz a ponte: acha o campo da página, diz ao sistema onde ele está e abre o painel.
//
// A porta de entrada do painel não é pública: é o `NSAutoFillHeuristicController` do AppKit
// (o mesmo que o menu "Senhas…" chama). Nos headers públicos não há nada equivalente. Tudo é
// conferido antes de chamar; se uma versão do macOS mudar isso, o botão avisa e nada quebra.
// O Crew nunca lê o Keychain nem vê as senhas: quem autentica, mostra e digita é o sistema.
//
// O que NÃO dá para app de terceiro: sugerir a senha do site sozinho ao focar o campo (como
// no Safari) e passkeys das Chaves do iCloud. As duas coisas pedem autorização de navegador
// dada pela Apple (ou domínio associado ao app, que só serve para site próprio).

/// A página do navegador: um WKWebView que aceita o comando "Senhas…" do sistema.
final class WebNav: WKWebView {
    private static let comandoSenhas = NSSelectorFromString("_handleInsertFromPasswordsCommand:")

    /// Editar > Preenchimento Automático > Senhas… (o item que o macOS põe no menu).
    @objc(_handleInsertFromPasswordsCommand:)
    func preencherSenha(_ sender: Any?) {
        Task { await SenhasNav.pedir(self) }
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == Self.comandoSenhas { return SenhasNav.disponivel }
        return super.validateUserInterfaceItem(item)
    }
}

@MainActor
enum SenhasNav {
    enum Resultado: Equatable {
        /// O painel do sistema foi pedido.
        case abriu
        /// A página não tem campo de texto em foco nem campo de senha à vista.
        case semCampo
        /// Este macOS não tem mais a porta de entrada do painel.
        case indisponivel
    }

    private static let seletorComRetangulo = NSSelectorFromString("_presentAutoFillPanelForTextInputContext:overrideAutoFillMode:selectedTextRect:")
    private static let seletorSimples = NSSelectorFromString("showAutoFillPasswordsPopoverForTextInputContext:")
    /// O modo "senhas" do painel (o mesmo que o menu do sistema passa).
    private static let modoSenhas = 1

    /// O controlador de preenchimento do AppKit (interno; nil se não existir mais).
    private static var controlador: NSObject? {
        guard let classe = NSClassFromString("NSAutoFillHeuristicController") as? NSObject.Type else { return nil }
        let unico = NSSelectorFromString("sharedInstance")
        guard classe.responds(to: unico) else { return nil }
        return classe.perform(unico)?.takeUnretainedValue() as? NSObject
    }

    static var disponivel: Bool {
        guard let c = controlador else { return false }
        return c.responds(to: seletorComRetangulo) || c.responds(to: seletorSimples)
    }

    /// Acha o campo: o que está em foco na página; sem foco em campo, o primeiro campo de
    /// senha à vista (que ganha o foco). Devolve o retângulo dele na página, em pontos de CSS.
    private static let acharCampo = """
    (() => {
      const some = ['button','submit','checkbox','radio','file','hidden','range','color','image','reset'];
      const editavel = e => !!e && ((e.tagName === 'INPUT' && !some.includes(e.type) && !e.disabled && !e.readOnly)
        || (e.tagName === 'TEXTAREA' && !e.disabled) || e.isContentEditable);
      const aVista = e => { const r = e.getBoundingClientRect(); const s = getComputedStyle(e);
        return r.width > 0 && r.height > 0 && s.visibility !== 'hidden' && s.display !== 'none'; };
      let e = document.activeElement;
      // Campo dentro de um quadro (iframe): o foco é do quadro; o texto vai para o campo dele.
      if (e && e.tagName === 'IFRAME') { const r = e.getBoundingClientRect(); return [r.left, r.top, Math.min(r.width, 320), Math.min(r.height, 36)]; }
      if (!editavel(e)) {
        e = [...document.querySelectorAll('input[type=password]')].find(x => editavel(x) && aVista(x));
        if (e) e.focus();
      }
      if (!editavel(e)) return null;
      const r = e.getBoundingClientRect();
      return [r.left, r.top, r.width, r.height];
    })()
    """

    /// Abre o painel de senhas do macOS sobre o campo da página.
    @discardableResult
    static func pedir(_ web: WKWebView) async -> Resultado {
        guard let c = controlador, disponivel, let janela = web.window else { return .indisponivel }
        let achado = try? await web.evaluateJavaScript(acharCampo, in: nil, contentWorld: .defaultClient)
        guard let n = achado as? [Double], n.count == 4 else { return .semCampo }

        // O texto escolhido é digitado em quem tem o cursor: tem de ser a página.
        if janela.firstResponder !== web { janela.makeFirstResponder(web) }
        guard let contexto = web.inputContext else { return .indisponivel }

        // Da página (CSS) para a tela.
        let z = web.pageZoom * web.magnification
        var r = NSRect(x: n[0] * z, y: n[1] * z, width: max(2, n[2] * z), height: max(2, n[3] * z))
        if !web.isFlipped { r.origin.y = web.bounds.height - r.maxY }
        r = r.intersection(web.bounds).isEmpty ? NSRect(x: 12, y: 12, width: 200, height: 24) : r.intersection(web.bounds)
        let naTela = janela.convertToScreen(web.convert(r, to: nil))

        if c.responds(to: seletorComRetangulo), let imp = c.method(for: seletorComRetangulo) {
            typealias Abrir = @convention(c) (AnyObject, Selector, AnyObject, Int, NSRect) -> Void
            unsafeBitCast(imp, to: Abrir.self)(c, seletorComRetangulo, contexto, modoSenhas, naTela)
        } else {
            c.perform(seletorSimples, with: contexto)
        }
        return .abriu
    }

    /// O app Senhas do macOS (para copiar à mão quando o painel não serve).
    static func abrirAppSenhas() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Passwords.app"))
    }
}

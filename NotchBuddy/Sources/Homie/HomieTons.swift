// Visual do Homie ("Polido") — peças de base: cor em tupla, tons de luz e sombra que não
// "sujam" de cinza, e o nível de detalhe por tamanho (o Homie de 20 pt não é o de 220 pt
// encolhido). Usado pelo corpo (HomieCorpo.swift) e pelo boné (HomieBone.swift).
import SwiftUI

typealias Cor3 = (CGFloat, CGFloat, CGFloat)

enum Tom {
    static func mix(_ a: Cor3, _ b: Cor3, _ t: CGFloat) -> Cor3 {
        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }
    static func claro(_ c: Cor3, _ t: CGFloat) -> Cor3 { mix(c, (1, 1, 1), t) }
    static func escuro(_ c: Cor3, _ t: CGFloat) -> Cor3 { (c.0 * (1 - t), c.1 * (1 - t), c.2 * (1 - t)) }
    static func luma(_ c: Cor3) -> CGFloat { 0.2126 * c.0 + 0.7152 * c.1 + 0.0722 * c.2 }
    /// Mais ou menos saturado, em volta da própria luminância.
    static func saturar(_ c: Cor3, _ k: CGFloat) -> Cor3 {
        let l = luma(c)
        func f(_ v: CGFloat) -> CGFloat { max(0, min(1, l + (v - l) * k)) }
        return (f(c.0), f(c.1), f(c.2))
    }
    /// Sombra da própria cor: escurece, satura um pouco e esfria (nunca preto por cima, que suja).
    static func sombra(_ c: Cor3, _ f: CGFloat) -> Cor3 {
        let d = saturar(escuro(c, f), 1 + 0.55 * f)
        return (max(0, d.0 - 0.035 * f), d.1, min(1, d.2 + 0.05 * f))
    }
    static func cor(_ c: Cor3, _ a: Double = 1) -> Color {
        Color(red: Double(c.0), green: Double(c.1), blue: Double(c.2)).opacity(a)
    }
}

/// Nível de detalhe pelo tamanho do desenho (R = raio de base do corpo, 0,3 × o lado da tela dele).
enum Detalhe {
    case micro    // até ~22 pt de tela (notch apertado, lista)
    case pequeno  // até ~44 pt (notch, barra lateral)
    case cheio
    init(R: CGFloat) { self = R < 6.6 ? .micro : R < 13.5 ? .pequeno : .cheio }
    /// Olhos crescem quando o desenho encolhe, para continuarem sendo "dois olhos".
    var olho: CGFloat { self == .micro ? 1.42 : self == .pequeno ? 1.24 : 1 }
    /// A aba engrossa quando encolhe, senão vira um fio.
    var aba: CGFloat { self == .micro ? 1.7 : self == .pequeno ? 1.35 : 1 }
    /// O olho já cresceu; a sobrancelha afina um pouco para não pesar.
    var sobrancelha: CGFloat { self == .cheio ? 0.92 : 0.92 * 0.82 }
}

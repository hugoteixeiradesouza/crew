import Foundation

/// Temperatura média da CPU pelo SMC. As chaves mudam a cada geração de chip.
/// Intel: TC0D/E/F/P/H.
enum LeitorTemperatura {
    private static let chaves: [String] = {
        var tam = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &tam, nil, 0)
        var buf = [CChar](repeating: 0, count: max(tam, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &tam, nil, 0)
        let chip = buf.textoC
        if chip.contains("M1") { return ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"] }
        if chip.contains("M2") { return ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"] }
        if chip.contains("M3") { return ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"] }
        if chip.contains("M4") { return ["Te05", "Te09", "Te0H", "Te0S", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"] }
        if chip.contains("M5") { return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K", "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"] }
        return []
    }()

    static func ler() -> Double? {
        for k in ["TC0D", "TC0E", "TC0F", "TC0P", "TC0H"] {
            if let v = SMC.shared.valor(k), v > 0, v < 110 { return v }
        }
        let vals = chaves.compactMap { SMC.shared.valor($0) }.filter { $0 > 0 && $0 < 110 }
        return vals.isEmpty ? nil : vals.reduce(0, +) / Double(vals.count)
    }
}

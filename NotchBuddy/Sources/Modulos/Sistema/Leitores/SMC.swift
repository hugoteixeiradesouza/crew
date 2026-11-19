//  Leitura do SMC (temperaturas).
//  Só leitura: o Crew não escreve no SMC (ventoinhas ficaram de fora).

import Foundation
import IOKit

final class SMC: @unchecked Sendable {
    static let shared = SMC()

    private var conexao: io_connect_t = 0
    private let trava = NSLock()
    private var infoCache: [UInt32: ChaveInfo] = [:]

    private struct ChaveInfo { var tamanho: IOByteCount32 = 0; var tipo: UInt32 = 0; var atributos: UInt8 = 0 }

    private struct DadosChave {
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        struct Versao { var major: CUnsignedChar = 0; var minor: CUnsignedChar = 0; var build: CUnsignedChar = 0
                        var reserved: CUnsignedChar = 0; var release: CUnsignedShort = 0 }
        struct Limite { var version: UInt16 = 0; var length: UInt16 = 0; var cpuPLimit: UInt32 = 0
                        var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
        var key: UInt32 = 0
        var vers = Versao()
        var pLimitData = Limite()
        var keyInfo = ChaveInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private init() {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &it) == kIOReturnSuccess else { return }
        let dev = IOIteratorNext(it)
        IOObjectRelease(it)
        guard dev != 0 else { return }
        _ = IOServiceOpen(dev, mach_task_self_, 0, &conexao)
        IOObjectRelease(dev)
    }

    private static func codigo(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
    private static func texto(_ c: UInt32) -> String {
        String(bytes: [UInt8(c >> 24 & 0xff), UInt8(c >> 16 & 0xff), UInt8(c >> 8 & 0xff), UInt8(c & 0xff)], encoding: .ascii) ?? ""
    }

    /// Valor numérico de uma chave (temperaturas em °C). nil se a chave não existe neste Mac.
    func valor(_ chave: String) -> Double? {
        guard conexao != 0, chave.utf8.count == 4 else { return nil }
        trava.lock(); defer { trava.unlock() }
        var entrada = DadosChave(), saida = DadosChave()
        entrada.key = Self.codigo(chave)
        let info: ChaveInfo
        if let c = infoCache[entrada.key] {
            info = c
        } else {
            entrada.data8 = 9  // readKeyInfo
            guard chamar(&entrada, &saida) == kIOReturnSuccess, saida.result == 0 else { return nil }
            info = saida.keyInfo
            infoCache[entrada.key] = info
        }
        entrada.keyInfo.tamanho = info.tamanho
        entrada.data8 = 5  // readBytes
        guard chamar(&entrada, &saida) == kIOReturnSuccess, saida.result == 0 else { return nil }
        let b = withUnsafeBytes(of: saida.bytes) { Array($0.prefix(Int(info.tamanho))) }
        guard b.contains(where: { $0 != 0 }) else { return nil }
        switch Self.texto(info.tipo) {
        case "flt ": return b.count >= 4 ? Double(b.withUnsafeBytes { $0.load(as: Float.self) }) : nil
        case "sp78": return Double(Int(b[0]) * 256 + Int(b[1])) / 256
        case "ui8 ": return Double(b[0])
        case "ui16": return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "fpe2": return Double((Int(b[0]) << 6) + (Int(b[1]) >> 2))
        default: return nil
        }
    }

    private func chamar(_ entrada: inout DadosChave, _ saida: inout DadosChave) -> kern_return_t {
        var tamanhoSaida = MemoryLayout<DadosChave>.stride
        return IOConnectCallStructMethod(conexao, 2, &entrada, MemoryLayout<DadosChave>.stride, &saida, &tamanhoSaida)
    }
}

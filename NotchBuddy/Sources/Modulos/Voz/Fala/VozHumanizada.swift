import Foundation

// Uma voz humanizada do Hugo: uma pasta em `motores/omnivoice/vozes/<id>/` com o áudio de
// referência (ref.wav, 24 kHz mono) e a ficha (voz.json). O motor fala "com a identidade" desse
// áudio, então a voz soa igual de uma fala para a outra. Nasce de dois jeitos: desenhada (o
// motor inventa uma voz pelos atributos e a amostra aprovada vira a referência) ou clonada de
// uma gravação — só de voz que é do Hugo ou de quem deixou.

struct VozHumanizada: Identifiable, Equatable, Codable {
    enum Origem: String, Codable { case desenhada, clonada }

    let id: String
    var nome: String
    let origem: Origem
    /// O que é dito no áudio de referência (o motor precisa do texto exato).
    let textoDaReferencia: String
    /// Atributos usados no desenho (vazio em voz clonada), já em português, para a tela.
    var descricao: String
    let criada: Date

    var pasta: URL { MotorOmniVoice.vozes.appendingPathComponent(id) }
    var referencia: URL { pasta.appendingPathComponent("ref.wav") }

    // MARK: Disco

    static func listar() -> [VozHumanizada] {
        let fm = FileManager.default
        let pastas = (try? fm.contentsOfDirectory(at: MotorOmniVoice.vozes, includingPropertiesForKeys: nil,
                                                  options: [.skipsHiddenFiles])) ?? []
        let leitor = JSONDecoder()
        leitor.dateDecodingStrategy = .iso8601
        return pastas.compactMap { p -> VozHumanizada? in
            guard let d = try? Data(contentsOf: p.appendingPathComponent("voz.json")),
                  let v = try? leitor.decode(VozHumanizada.self, from: d),
                  v.id == p.lastPathComponent, fm.fileExists(atPath: v.referencia.path) else { return nil }
            return v
        }.sorted { $0.criada < $1.criada }
    }

    /// Grava a voz (ficha + áudio de referência já em WAV).
    static func guardar(nome: String, origem: Origem, texto: String, descricao: String, wav: Data) throws -> VozHumanizada {
        let fm = FileManager.default
        let base = identificador(nome)
        var id = base
        var n = 2
        while fm.fileExists(atPath: MotorOmniVoice.vozes.appendingPathComponent(id).path) { id = "\(base)-\(n)"; n += 1 }
        let voz = VozHumanizada(id: id, nome: nome.trimmingCharacters(in: .whitespacesAndNewlines), origem: origem,
                                textoDaReferencia: texto, descricao: descricao, criada: Date())
        try fm.createDirectory(at: voz.pasta, withIntermediateDirectories: true)
        try wav.write(to: voz.referencia, options: .atomic)
        let escritor = JSONEncoder()
        escritor.dateEncodingStrategy = .iso8601
        escritor.outputFormatting = [.prettyPrinted, .sortedKeys]
        try escritor.encode(voz).write(to: voz.pasta.appendingPathComponent("voz.json"), options: .atomic)
        return voz
    }

    func apagar() { try? FileManager.default.removeItem(at: pasta) }

    /// Nome de pasta (e nome da voz dentro do motor): só letras minúsculas, números e hífen.
    static func identificador(_ texto: String) -> String {
        let semAcento = texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")).lowercased()
        var saida = ""
        for c in semAcento.unicodeScalars {
            if CharacterSet.alphanumerics.contains(c), c.isASCII { saida.unicodeScalars.append(c) }
            else if !saida.isEmpty, !saida.hasSuffix("-") { saida.append("-") }
        }
        let limpo = String(saida.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40))
        return limpo.isEmpty ? "voz" : limpo
    }

    /// Converte uma gravação qualquer (m4a, mp3, wav, aiff) para o WAV que o motor lê
    /// (24 kHz, mono, 16 bits), com o conversor do macOS. Fora da main.
    static func converter(_ origem: URL) async -> Result<Data, ServidorOmniVoice.Falha> {
        let saida = FileManager.default.temporaryDirectory.appendingPathComponent("crew-voz-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: saida) }
        let r = await Processo.rodar("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@24000", "-c", "1", origem.path, saida.path],
                                     tempoMax: 60)
        guard r.ok, let d = try? Data(contentsOf: saida), d.count > 44 else {
            return .failure(.init(texto: "Não consegui ler esse áudio. Use uma gravação em WAV, M4A, MP3 ou AIFF."))
        }
        // 24 kHz mono 16 bits = 48 000 bytes por segundo
        let segundos = Double(d.count - 44) / 48_000
        if segundos < 2 { return .failure(.init(texto: "A gravação é curta demais (menos de 2 segundos). O ideal é de 5 a 15 segundos.")) }
        if segundos > 30 { return .failure(.init(texto: "A gravação é longa demais (\(Int(segundos)) segundos). Corte um trecho de 5 a 15 segundos.")) }
        return .success(d)
    }
}

/// Os atributos de uma voz desenhada: o que o Hugo escolhe na tela e o que o motor entende.
struct DesenhoDeVoz: Equatable {
    enum Genero: String, CaseIterable, Identifiable {
        case feminina = "female", masculina = "male"
        var id: String { rawValue }
        var rotulo: String { self == .feminina ? "Feminina" : "Masculina" }
    }

    enum Idade: String, CaseIterable, Identifiable {
        case adolescente = "teenager", jovem = "young adult", meiaIdade = "middle-aged", idosa = "elderly"
        var id: String { rawValue }
        var rotulo: String {
            switch self {
            case .adolescente: "Adolescente"
            case .jovem: "Jovem adulta"
            case .meiaIdade: "Meia-idade"
            case .idosa: "Idosa"
            }
        }
    }

    enum Tom: String, CaseIterable, Identifiable {
        case muitoGrave = "very low pitch", grave = "low pitch", medio = "moderate pitch", agudo = "high pitch"
        var id: String { rawValue }
        var rotulo: String {
            switch self {
            case .muitoGrave: "Muito grave"
            case .grave: "Grave"
            case .medio: "Médio"
            case .agudo: "Agudo"
            }
        }
    }

    var genero = Genero.feminina
    var idade = Idade.jovem
    var tom = Tom.medio

    /// O que vai para o motor (os atributos são em inglês, separados por vírgula).
    var instrucoes: String { "\(genero.rawValue), \(idade.rawValue), \(tom.rawValue)" }
    var descricao: String { "\(genero.rotulo), \(idade.rotulo.lowercased()), tom \(tom.rotulo.lowercased())" }
}

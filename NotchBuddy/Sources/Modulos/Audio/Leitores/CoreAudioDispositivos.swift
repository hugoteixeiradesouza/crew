import CoreAudio
import AudioToolbox
import Foundation

// Leitura e escrita dos dispositivos de áudio pelo Core Audio (HAL), escrito do zero.
// Só propriedades: nada aqui abre fluxo de áudio, então o macOS não pede permissão de microfone.

/// Como o dispositivo está ligado ao Mac.
enum Transporte: String, Sendable {
    case embutido, bluetooth, usb, hdmi, displayPort, airPlay, thunderbolt, pci, iPhone, virtual, agregado, outro

    var nome: String {
        switch self {
        case .embutido: "Embutido"
        case .bluetooth: "Bluetooth"
        case .usb: "USB"
        case .hdmi: "HDMI"
        case .displayPort: "DisplayPort"
        case .airPlay: "AirPlay"
        case .thunderbolt: "Thunderbolt"
        case .pci: "PCI"
        case .iPhone: "iPhone"
        case .virtual: "Virtual"
        case .agregado: "Agregado"
        case .outro: "Outro"
        }
    }

    init(codigo: UInt32) {
        switch codigo {
        case kAudioDeviceTransportTypeBuiltIn: self = .embutido
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeHDMI: self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
        case kAudioDeviceTransportTypePCI: self = .pci
        case kAudioDeviceTransportTypeContinuityCaptureWired, kAudioDeviceTransportTypeContinuityCaptureWireless: self = .iPhone
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: self = .agregado
        default: self = .outro
        }
    }
}

struct DispositivoAudio: Identifiable, Equatable, Sendable {
    let id: AudioObjectID
    let uid: String
    let nome: String
    let transporte: Transporte
    let temSaida: Bool
    let temEntrada: Bool
    /// O macOS deixa mudar o volume dele (HDMI, DAC e alguns USB não deixam).
    let volumeNoHardware: Bool

    /// Ícone (SF Symbol) para saída ou entrada.
    func icone(entrada: Bool) -> String {
        let n = nome.lowercased()
        switch transporte {
        case .embutido:
            if entrada { return "laptopcomputer" }
            return n.contains("fone") || n.contains("headphone") ? "headphones" : "laptopcomputer"
        case .bluetooth:
            if n.contains("airpods max") { return "airpodsmax" }
            if n.contains("airpods pro") { return "airpodspro" }
            if n.contains("airpods") { return "airpods" }
            return entrada ? "mic" : "headphones"
        case .usb: return entrada ? "mic" : "hifispeaker"
        case .hdmi, .displayPort, .thunderbolt: return "tv"
        case .airPlay: return "airplayaudio"
        case .iPhone: return "iphone"
        case .virtual, .agregado: return "waveform"
        case .pci, .outro: return entrada ? "mic" : "speaker.wave.2"
        }
    }
}

enum CoreAudioHW {
    static let sistema = AudioObjectID(kAudioObjectSystemObject)

    static func endereco(_ sel: AudioObjectPropertySelector,
                         _ escopo: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: sel, mScope: escopo, mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: Leitura

    static func dispositivos() -> [DispositivoAudio] {
        var addr = endereco(kAudioHardwarePropertyDevices)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(sistema, &addr, 0, nil, &tam) == noErr, tam > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(tam) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sistema, &addr, 0, nil, &tam, &ids) == noErr else { return [] }
        return ids.compactMap(ler)
    }

    /// Um dispositivo, ou nil se ele for oculto/sem fluxo (agregados privados de outros apps etc.).
    static func ler(_ id: AudioObjectID) -> DispositivoAudio? {
        guard let uid = texto(id, kAudioDevicePropertyDeviceUID), !uid.isEmpty else { return nil }
        // Os aggregates do volume por app (privados, do próprio Crew) não são dispositivos do Hugo.
        if uid.hasPrefix(GuardaTaps.prefixoUID) { return nil }
        if uint32(id, kAudioDevicePropertyIsHidden) == 1 { return nil }
        let saida = fluxos(id, kAudioObjectPropertyScopeOutput) > 0
            && uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput) != 0
        let entrada = fluxos(id, kAudioObjectPropertyScopeInput) > 0
            && uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeInput) != 0
        guard saida || entrada else { return nil }
        let nome = texto(id, kAudioObjectPropertyName) ?? uid
        let transporte = Transporte(codigo: uint32(id, kAudioDevicePropertyTransportType) ?? 0)
        return DispositivoAudio(id: id, uid: uid, nome: nome, transporte: transporte,
                                temSaida: saida, temEntrada: entrada,
                                volumeNoHardware: saida && volumeAjustavel(id))
    }

    enum Papel: Sendable {
        case saida, entrada, somDoSistema
        var seletor: AudioObjectPropertySelector {
            switch self {
            case .saida: kAudioHardwarePropertyDefaultOutputDevice
            case .entrada: kAudioHardwarePropertyDefaultInputDevice
            case .somDoSistema: kAudioHardwarePropertyDefaultSystemOutputDevice
            }
        }
    }

    static func padrao(_ papel: Papel) -> AudioObjectID {
        var addr = endereco(papel.seletor)
        var id = AudioObjectID(0)
        var tam = UInt32(MemoryLayout<AudioObjectID>.size)
        return AudioObjectGetPropertyData(sistema, &addr, 0, nil, &tam, &id) == noErr ? id : 0
    }

    // MARK: Escrita

    @discardableResult
    static func definirPadrao(_ papel: Papel, _ id: AudioObjectID) -> Bool {
        var addr = endereco(papel.seletor)
        var valor = id
        return AudioObjectSetPropertyData(sistema, &addr, 0, nil, UInt32(MemoryLayout<AudioObjectID>.size), &valor) == noErr
    }

    // MARK: Auxiliares

    private static func texto(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
        var addr = endereco(sel)
        var valor: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let st = withUnsafeMutablePointer(to: &valor) { AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, $0) }
        guard st == noErr, let v = valor else { return nil }
        return v.takeRetainedValue() as String
    }

    private static func uint32(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector,
                               _ escopo: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var addr = endereco(sel, escopo)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var v: UInt32 = 0
        var tam = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &tam, &v) == noErr ? v : nil
    }

    private static func fluxos(_ id: AudioObjectID, _ escopo: AudioObjectPropertyScope) -> Int {
        var addr = endereco(kAudioDevicePropertyStreams, escopo)
        var tam: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &tam) == noErr else { return 0 }
        return Int(tam) / MemoryLayout<AudioStreamID>.size
    }

    private static func volumeAjustavel(_ id: AudioObjectID) -> Bool {
        var addr = endereco(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var pode: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &pode) == noErr && pode.boolValue
    }
}

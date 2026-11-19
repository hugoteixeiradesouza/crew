// Só para teste: mede (RMS por segundo) o que sai na saída padrão, depois do mudo dos taps,
// com um tap global (não silencia ninguém). Escreve em argv[1].
import AppKit
import CoreAudio
import AudioToolbox
func endereco(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain) }
let saidaArq = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/medidor.txt"
FileManager.default.createFile(atPath: saidaArq, contents: nil)
let fh = FileHandle(forWritingAtPath: saidaArq)!
func escreve(_ s: String) { fh.write((s + "\n").data(using: .utf8)!) }
var a = endereco(kAudioHardwarePropertyDefaultOutputDevice)
var dev = AudioObjectID(0); var tam = UInt32(4)
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &tam, &dev)
a = endereco(kAudioDevicePropertyDeviceUID)
var uidCF: Unmanaged<CFString>?; tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
_ = withUnsafeMutablePointer(to: &uidCF) { AudioObjectGetPropertyData(dev, &a, 0, nil, &tam, $0) }
let uid = uidCF!.takeRetainedValue() as String
// exclui o próprio medidor
var meuObj = AudioObjectID(0)
var pid = getpid()
a = endereco(kAudioHardwarePropertyTranslatePIDToProcessObject)
tam = 4
AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, UInt32(MemoryLayout<pid_t>.size), &pid, &tam, &meuObj)
let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: meuObj != 0 ? [meuObj] : [])
desc.isPrivate = true
desc.muteBehavior = .unmuted
var tap = AudioObjectID(0)
var st = AudioHardwareCreateProcessTap(desc, &tap)
escreve("tap \(st) uid \(uid)")
let agg: [String: Any] = [kAudioAggregateDeviceNameKey: "medidor-teste", kAudioAggregateDeviceUIDKey: UUID().uuidString,
    kAudioAggregateDeviceMainSubDeviceKey: uid, kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: uid]],
    kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]]]
var aggID = AudioObjectID(0)
st = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
escreve("agg \(st)")
final class Soma: @unchecked Sendable { var s: Double = 0; var n: Int = 0; let l = NSLock() }
let soma = Soma()
var proc: AudioDeviceIOProcID?
st = AudioDeviceCreateIOProcIDWithBlock(&proc, aggID, nil) { _, entrada, _, _, _ in
    let bufs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: entrada))
    var s = 0.0, n = 0
    for b in bufs { guard let d = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
        let c = Int(b.mDataByteSize) / 4; for i in 0..<c { s += Double(d[i] * d[i]) }; n += c }
    soma.l.lock(); soma.s += s; soma.n += n; soma.l.unlock()
}
escreve("proc \(st)")
st = AudioDeviceStart(aggID, proc)
escreve("start \(st)")
let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    soma.l.lock(); let r = soma.n > 0 ? (soma.s / Double(soma.n)).squareRoot() : -1; soma.s = 0; soma.n = 0; soma.l.unlock()
    escreve("\(f.string(from: Date())) rms \(String(format: "%.5f", r))")
}
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()

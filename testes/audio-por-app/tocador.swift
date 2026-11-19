// Só para teste: toca um seno de 440 Hz baixo, em laço, como app "regular".
import AppKit
import AVFoundation
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let motor = AVAudioEngine()
var fase: Double = 0
let taxa = motor.outputNode.outputFormat(forBus: 0).sampleRate
let fonte = AVAudioSourceNode { _, _, n, abl -> OSStatus in
    let bufs = UnsafeMutableAudioBufferListPointer(abl)
    for f in 0..<Int(n) {
        let v = Float(sin(fase) * 0.03)
        fase += 2 * .pi * 440 / taxa
        for b in bufs { b.mData!.assumingMemoryBound(to: Float.self)[f] = v }
    }
    return noErr
}
let fmt = AVAudioFormat(standardFormatWithSampleRate: taxa, channels: 2)!
motor.attach(fonte)
motor.connect(fonte, to: motor.mainMixerNode, format: fmt)
try! motor.start()
app.run()

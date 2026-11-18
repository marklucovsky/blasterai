// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
// Renders what the keyboard would say, with the voices on this Mac, so it can
// be judged by ear. See docs/keyboard-design.md.
//
//     swift tools/speech_probe/probe.swift <out-dir> [voice-id ...]
//
// With no voice ids it uses every English voice of Enhanced or Premium
// quality, plus Samantha (compact) as the baseline the simulator has.
//
// Three groups:
//   - typing:  each case raw (what the voice does alone) and normalised
//              (what SpeechNormalizer hands it). The normalised strings are
//              copied from SpeechNormalizerTests; keep them in step.
//   - letters: ways to make a lone letter say its name.
//   - ipa:     phonics sounds through AVSpeechSynthesisIPANotationAttribute,
//              the question PR B is asked to answer for phonetic keys.
//
// Writes <out-dir>/<voice>/<group>-<n>.caf and <out-dir>/index.html, a
// listening sheet. The Mac's voices are the iPad's voices (same engine and
// downloads), so what is heard here is what a child hears.

import AVFoundation
import Foundation

struct Case { let group: String; let label: String; let text: String; let ipa: String? }

let typing: [(String, String)] = [
    ("2 + 2 = 4", "2 plus 2 equals 4"),
    ("12 ÷ 4 = 3", "12 divided by 4 equals 3"),
    ("6 × 7", "6 times 7"),
    ("6 x 7", "6 times 7"),
    ("10 - 3 = 7", "10 minus 3 equals 7"),
    ("3 < 5", "3 is less than 5"),
    ("9 > 2", "9 is greater than 2"),
    ("5/3", "5 thirds"),
    ("3/4", "3 fourths"),
    ("1/2", "1 half"),
    ("5/32", "5 over 32"),
    ("$5", "5 dollars"),
    ("$2.50", "2 dollars and 50 cents"),
    ("50%", "50 percent"),
    ("3:00", "3 o'clock"),
    ("3:15", "3 15"),
    ("I am 7", "I am 7"),
    ("+", "plus"),
    ("-", "minus"),
    ("÷", "divided by"),
    ("=", "equals"),
    (":15", "fifteen"),
    (",", "comma"),
]

let letters: [(String, String)] = [
    ("a", "a"), ("A", "A"), ("a.", "a."), ("ay", "ay"),
    ("i", "i"), ("I", "I"), ("i.", "i."),
    ("e", "e"), ("o", "o"), ("u", "u"), ("y", "y"), ("w", "w"), ("z", "z"),
]

/// Phonics keys as TouchChat has them, and the vowels short and long.
let ipa: [(String, String)] = [
    ("ch", "tʃ"), ("sh", "ʃ"), ("th (thin)", "θ"), ("th (this)", "ð"), ("ph", "f"),
    ("short a", "æ"), ("short e", "ɛ"), ("short i", "ɪ"), ("short o", "ɑ"), ("short u", "ʌ"),
    ("long a", "eɪ"), ("long e", "i"), ("long i", "aɪ"), ("long o", "oʊ"), ("long u", "ju"),
    ("b", "b"), ("m", "m"), ("s", "s"),
    // A sound inside a syllable, in case a lone consonant is dropped.
    ("chuh", "tʃʌ"), ("shh", "ʃː"),
]

var cases: [Case] = []
for (i, t) in typing.enumerated() {
    cases.append(Case(group: "typing-\(i)-raw", label: t.0, text: t.0, ipa: nil))
    cases.append(Case(group: "typing-\(i)-norm", label: t.1, text: t.1, ipa: nil))
}
for (i, l) in letters.enumerated() {
    cases.append(Case(group: "letters-\(i)", label: l.0, text: l.1, ipa: nil))
}
for (i, p) in ipa.enumerated() {
    cases.append(Case(group: "ipa-\(i)", label: "\(p.0) /\(p.1)/", text: p.0, ipa: p.1))
}

let args = CommandLine.arguments.dropFirst()
guard let outDir = args.first else {
    FileHandle.standardError.write("usage: probe.swift <out-dir> [voice-id ...]\n".data(using: .utf8)!)
    exit(2)
}
let out = URL(fileURLWithPath: outDir)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

var voices: [AVSpeechSynthesisVoice] = args.dropFirst().compactMap { AVSpeechSynthesisVoice(identifier: $0) }
if voices.isEmpty {
    voices = AVSpeechSynthesisVoice.speechVoices().filter {
        $0.language.hasPrefix("en") && $0.quality != .default
    }
    if let baseline = AVSpeechSynthesisVoice(identifier: "com.apple.voice.compact.en-US.Samantha") {
        voices.insert(baseline, at: 0)
    }
}
print("voices:", voices.map { "\($0.name) [\($0.quality == .premium ? "premium" : $0.quality == .enhanced ? "enhanced" : "compact")]" })

let synth = AVSpeechSynthesizer()

/// Render one utterance to a file; returns its length in seconds (0 = silence).
func render(_ c: Case, voice: AVSpeechSynthesisVoice, to url: URL) -> Double {
    let utterance: AVSpeechUtterance
    if let ipa = c.ipa {
        let key = NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute)
        utterance = AVSpeechUtterance(attributedString:
            NSAttributedString(string: c.text, attributes: [key: ipa]))
    } else {
        utterance = AVSpeechUtterance(string: c.text)
    }
    utterance.voice = voice
    var file: AVAudioFile?
    var frames: AVAudioFramePosition = 0
    var rate = 22050.0
    let done = DispatchSemaphore(value: 0)
    var finished = false
    synth.write(utterance) { buffer in
        guard let pcm = buffer as? AVAudioPCMBuffer else { return }
        if pcm.frameLength == 0 {
            if !finished { finished = true; done.signal() }
            return
        }
        if file == nil {
            rate = pcm.format.sampleRate
            file = try? AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                    commonFormat: pcm.format.commonFormat,
                                    interleaved: pcm.format.isInterleaved)
        }
        try? file?.write(from: pcm)
        frames += AVAudioFramePosition(pcm.frameLength)
    }
    while done.wait(timeout: .now() + 0.05) == .timedOut {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return Double(frames) / rate
}

var rows: [String: [String: (file: String, seconds: Double)]] = [:]
for voice in voices {
    let dir = out.appendingPathComponent(voice.name)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for c in cases {
        let url = dir.appendingPathComponent("\(c.group).caf")
        let seconds = render(c, voice: voice, to: url)
        rows[c.group, default: [:]][voice.name] = ("\(voice.name)/\(c.group).caf", seconds)
    }
    print("rendered \(cases.count) for \(voice.name)")
}

// A listening sheet: Safari plays .caf.
func esc(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
}
var html = """
<!doctype html><meta charset=utf-8><title>Keyboard speech probe</title>
<style>body{font:15px -apple-system,sans-serif;margin:24px}table{border-collapse:collapse}
td,th{border:1px solid #ccc;padding:4px 8px;vertical-align:middle}h2{margin-top:32px}
.silent{color:#b00}audio{height:28px;width:180px}</style>
<h1>Keyboard speech probe</h1><p>Rendered by tools/speech_probe/probe.swift. Seconds under each
player; <span class=silent>0.00</span> means the voice said nothing.</p>
"""
let header = "<tr><th>case</th>" + voices.map { "<th>\(esc($0.name))</th>" }.joined() + "</tr>"
func cell(_ group: String, _ voice: AVSpeechSynthesisVoice) -> String {
    guard let r = rows[group]?[voice.name] else { return "<td></td>" }
    let secs = String(format: "%.2f", r.seconds)
    return "<td><audio controls preload=none src='\(r.file)'></audio><br><span class='\(r.seconds < 0.05 ? "silent" : "")'>\(secs)s</span></td>"
}
html += "<h2>Typing: raw, then normalised</h2><table>\(header)"
for (i, t) in typing.enumerated() {
    html += "<tr><td><b>\(esc(t.0))</b> raw</td>" + voices.map { cell("typing-\(i)-raw", $0) }.joined() + "</tr>"
    html += "<tr><td>→ “\(esc(t.1))”</td>" + voices.map { cell("typing-\(i)-norm", $0) }.joined() + "</tr>"
}
html += "</table><h2>A lone letter</h2><table>\(header)"
for (i, l) in letters.enumerated() {
    html += "<tr><td>\(esc(l.0))</td>" + voices.map { cell("letters-\(i)", $0) }.joined() + "</tr>"
}
html += "</table><h2>Phonics through IPA</h2><table>\(header)"
for (i, p) in ipa.enumerated() {
    html += "<tr><td>\(esc(p.0)) /\(esc(p.1))/</td>" + voices.map { cell("ipa-\(i)", $0) }.joined() + "</tr>"
}
html += "</table>"
try html.write(to: out.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
print("wrote \(out.appendingPathComponent("index.html").path)")

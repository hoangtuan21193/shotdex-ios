// Video Studio fixtures (FS-12.11 · 12 · 13 §9): the sample project's media,
// made from nothing — drawn landscapes with no people in them, generated
// video, the system's speech synthesizer for "voices", and synthetic music —
// so no face, no real voice and no copyrighted track ever reaches a
// simulator or a screenshot. Compiled and run by Tools/video-fixtures.
//
//   video-fixtures <out-dir> [media|music|all]
//
// media: Falls.jpg (photo) · Coast.mov 6.2 s · Lake.mov 5.0 s · Night.jpg
//        (photo) · Forest.mov 6.8 s. Each video carries quiet room tone
//        (−50 dBFS) and one spoken stretch, placed so that with the clips in
//        that order (3.0 · 6.2 · 5.0 · 3.0 · 6.8) the speech falls at
//        4.2–7.4, 10.8–13.0 and 18.7–21.9 s of the timeline (FS-12.13 §7).
//        Dates step one minute apart, Falls first, so the library lists them
//        together in project order.
// music: MorningDrive.m4a (96 BPM click + bass, bar accent, 60 s),
//        Sine440.m4a (440 Hz, 30 s, −12 dBFS), LongTrack.m4a (3:24 at
//        44.1 kHz, 112 BPM) and Noise.m4a (30 s of white noise).
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: video-fixtures <out-dir> [media|music|all]\n".data(using: .utf8)!)
    exit(64)
}
let outDir = URL(fileURLWithPath: arguments[1], isDirectory: true)
let which = arguments.count >= 3 ? arguments[2] : "all"
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let baseDate: Date = {
    var components = DateComponents()
    components.year = 2026; components.month = 10; components.day = 1
    components.hour = 9; components.minute = 0
    components.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: components)!
}()

// MARK: - Pictures

/// A drawn landscape: a sky gradient, a sun or moon, two ridges and water.
/// `phase` slides the ridges and the sun so a video's frames move.
func drawLandscape(_ context: CGContext, width: Int, height: Int, palette: Int, phase: Double, label: String?) {
    let w = CGFloat(width), h = CGFloat(height)
    let skies: [(CGColor, CGColor)] = [
        (CGColor(red: 0.42, green: 0.70, blue: 0.95, alpha: 1), CGColor(red: 0.92, green: 0.95, blue: 1.0, alpha: 1)),
        (CGColor(red: 0.98, green: 0.55, blue: 0.30, alpha: 1), CGColor(red: 0.30, green: 0.20, blue: 0.45, alpha: 1)),
        (CGColor(red: 0.20, green: 0.55, blue: 0.45, alpha: 1), CGColor(red: 0.80, green: 0.92, blue: 0.85, alpha: 1)),
        (CGColor(red: 0.05, green: 0.07, blue: 0.20, alpha: 1), CGColor(red: 0.18, green: 0.22, blue: 0.40, alpha: 1)),
        (CGColor(red: 0.30, green: 0.45, blue: 0.25, alpha: 1), CGColor(red: 0.75, green: 0.85, blue: 0.60, alpha: 1)),
    ]
    let sky = skies[palette % skies.count]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [sky.0, sky.1] as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h * 0.35), options: [])
    // Sun or moon.
    let sunX = w * CGFloat(0.2 + 0.6 * (phase.truncatingRemainder(dividingBy: 1)))
    context.setFillColor(palette == 3 ? CGColor(red: 0.95, green: 0.95, blue: 0.85, alpha: 1) : CGColor(red: 1, green: 0.85, blue: 0.35, alpha: 1))
    context.fillEllipse(in: CGRect(x: sunX, y: h * 0.70, width: h * 0.12, height: h * 0.12))
    // Two ridges.
    for (layer, tone) in [(0, 0.35), (1, 0.18)] {
        context.setFillColor(CGColor(red: tone * 0.6, green: tone, blue: tone * 0.8, alpha: 1))
        context.beginPath()
        context.move(to: CGPoint(x: 0, y: 0))
        let steps = 24
        for step in 0...steps {
            let x = w * CGFloat(step) / CGFloat(steps)
            let wave = sin(Double(step) * (0.7 + Double(layer) * 0.4) + phase * 6.0 + Double(palette))
            let y = h * (0.45 - 0.12 * CGFloat(layer)) + h * 0.08 * CGFloat(wave)
            context.addLine(to: CGPoint(x: x, y: y))
        }
        context.addLine(to: CGPoint(x: w, y: 0))
        context.closePath()
        context.fillPath()
    }
    // Water.
    context.setFillColor(CGColor(red: 0.10, green: 0.25, blue: 0.40, alpha: 0.85))
    context.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.12))
    if let label {
        // A block per letter, not text: CoreText is not needed to tell clips apart.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        for (index, _) in label.enumerated() {
            context.fill(CGRect(x: w * 0.05 + CGFloat(index) * h * 0.05, y: h * 0.9, width: h * 0.035, height: h * 0.05))
        }
    }
}

func writePhoto(_ name: String, palette: Int, date: Date) throws {
    let width = 1920, height = 1080
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    drawLandscape(context, width: width, height: height, palette: palette, phase: 0.3, label: name)
    let image = context.makeImage()!
    let url = outDir.appendingPathComponent("\(name).jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    formatter.timeZone = TimeZone(identifier: "UTC")
    let stamp = formatter.string(from: date)
    let properties: [CFString: Any] = [
        kCGImagePropertyExifDictionary: [
            kCGImagePropertyExifDateTimeOriginal: stamp,
            kCGImagePropertyExifDateTimeDigitized: stamp,
        ],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFDateTime: stamp],
        kCGImageDestinationLossyCompressionQuality: 0.85,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "fixtures", code: 1) }
    print("wrote \(url.lastPathComponent)")
}

// MARK: - Sound

let audioRate = 44_100.0

/// The system speech synthesizer's voice — not a person's — as mono floats
/// at `audioRate`.
func spoken(_ text: String) throws -> [Float] {
    let speechFile = FileManager.default.temporaryDirectory.appendingPathComponent("vf-say-\(UUID().uuidString).caf")
    defer { try? FileManager.default.removeItem(at: speechFile) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    process.arguments = ["-o", speechFile.path, "--data-format=LEF32@44100", text]
    try process.run()
    process.waitUntilExit()
    let file = try AVAudioFile(forReading: speechFile)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: audioRate, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
}

/// Room tone at about −50 dBFS RMS, with one spoken stretch fitted into
/// `voice` (source seconds): the speech is repeated or cut to fill it.
func clipSound(seconds: Double, voice: ClosedRange<Double>?, text: String) throws -> [Float] {
    var generator = SystemRandomNumberGenerator()
    let count = Int(seconds * audioRate)
    let noiseAmplitude: Float = 0.00316 * 1.732  // uniform ±a has RMS a/√3 → −50 dBFS
    var samples = (0..<count).map { _ in Float.random(in: -noiseAmplitude...noiseAmplitude, using: &generator) }
    if let voice {
        let speech = try spoken(text)
        let start = Int(voice.lowerBound * audioRate)
        let end = min(count, Int(voice.upperBound * audioRate))
        var cursor = 0
        // Trim the synthesizer's own leading and trailing silence first.
        let threshold: Float = 0.01
        let first = speech.firstIndex { abs($0) > threshold } ?? 0
        let last = speech.lastIndex { abs($0) > threshold } ?? (speech.count - 1)
        let core = Array(speech[first...last])
        for index in start..<end {
            samples[index] += core[cursor % core.count] * 0.8
            cursor += 1
        }
    }
    return samples
}

/// 96 BPM 4/4 click with a bass note on every beat; beat 1 of each bar is
/// twice as loud, so the bar's downbeat is the strongest low phase.
func clickTrack(bpm: Double, seconds: Double, leadingSilence: Double = 0) -> [Float] {
    let count = Int(seconds * audioRate)
    var samples = [Float](repeating: 0, count: count)
    let beat = 60.0 / bpm
    var index = 0
    var time = leadingSilence
    while time < seconds {
        let accent: Float = index % 4 == 0 ? 1.0 : 0.5
        let start = Int(time * audioRate)
        for n in 0..<Int(0.12 * audioRate) where start + n < count {
            let t = Double(n) / audioRate
            let envelope = Float(exp(-t * 30))
            let click = Float(sin(2 * .pi * 1_800 * t)) * Float(exp(-t * 120))
            let bass = Float(sin(2 * .pi * 55 * t)) * envelope
            samples[start + n] += accent * (0.35 * click + 0.45 * bass)
        }
        index += 1
        time = leadingSilence + Double(index) * beat
    }
    return samples
}

func sine(_ frequency: Double, seconds: Double, dbfs: Double) -> [Float] {
    let amplitude = pow(10, dbfs / 20) * 1.414
    return (0..<Int(seconds * audioRate)).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / audioRate)) }
}

func writeAudio(_ name: String, samples: [Float]) throws {
    let url = outDir.appendingPathComponent("\(name).m4a")
    try? FileManager.default.removeItem(at: url)
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: audioRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 128_000,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: audioRate, channels: 1, interleaved: false)!
    let chunk = 44_100
    var offset = 0
    while offset < samples.count {
        let length = min(chunk, samples.count - offset)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length))!
        buffer.frameLength = AVAudioFrameCount(length)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress! + offset, count: length)
        }
        try file.write(from: buffer)
        offset += length
    }
    print("wrote \(url.lastPathComponent)")
}

// MARK: - Video

func writeVideo(_ name: String, seconds: Double, palette: Int, date: Date, sound: [Float]) throws {
    let url = outDir.appendingPathComponent("\(name).mov")
    try? FileManager.default.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let width = 1280, height = 720, fps: Int32 = 30
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    video.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: audioRate, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 96_000,
    ])
    audio.expectsMediaDataInRealTime = false
    writer.add(video)
    writer.add(audio)
    let creation = AVMutableMetadataItem()
    creation.identifier = .quickTimeMetadataCreationDate
    creation.value = ISO8601DateFormatter().string(from: date) as NSString
    creation.dataType = kCMMetadataBaseDataType_UTF8 as String
    let common = AVMutableMetadataItem()
    common.identifier = .commonIdentifierCreationDate
    common.value = ISO8601DateFormatter().string(from: date) as NSString
    writer.metadata = [creation, common]
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    // The writer interleaves its inputs: feed whichever is behind in time,
    // or one input's queue fills and waits for the other forever.
    let frames = Int((seconds * Double(fps)).rounded())
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: audioRate, channels: 1, interleaved: false)!
    var description: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
        allocator: nil, asbd: format.streamDescription, layoutSize: 0, layout: nil,
        magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description
    )
    let chunk = 4_410
    var frame = 0
    var offset = 0
    var videoDone = false, audioDone = false
    while !videoDone || !audioDone {
        let videoTime = Double(frame) / Double(fps)
        let audioTime = Double(offset) / audioRate
        if !videoDone, video.isReadyForMoreMediaData, audioDone || videoTime <= audioTime {
            if frame >= frames {
                video.markAsFinished()
                videoDone = true
                continue
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            guard let buffer else { throw NSError(domain: "fixtures", code: 2) }
            CVPixelBufferLockBaseAddress(buffer, [])
            let context = CGContext(
                data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )!
            drawLandscape(context, width: width, height: height, palette: palette, phase: Double(frame) / Double(frames), label: name)
            CVPixelBufferUnlockBaseAddress(buffer, [])
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
            frame += 1
        } else if !audioDone, audio.isReadyForMoreMediaData {
            if offset >= sound.count {
                audio.markAsFinished()
                audioDone = true
                continue
            }
            let length = min(chunk, sound.count - offset)
            var block: CMBlockBuffer?
            let bytes = length * MemoryLayout<Float>.size
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil, customBlockSource: nil,
                offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block
            )
            sound.withUnsafeBytes { raw in
                _ = CMBlockBufferReplaceDataBytes(
                    with: raw.baseAddress! + offset * MemoryLayout<Float>.size, blockBuffer: block!,
                    offsetIntoDestination: 0, dataLength: bytes
                )
            }
            var sample: CMSampleBuffer?
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(
                allocator: nil, dataBuffer: block!, formatDescription: description!, sampleCount: length,
                presentationTimeStamp: CMTime(value: CMTimeValue(offset), timescale: CMTimeScale(audioRate)),
                packetDescriptions: nil, sampleBufferOut: &sample
            )
            audio.append(sample!)
            offset += length
        } else {
            Thread.sleep(forTimeInterval: 0.002)
        }
    }

    let done = DispatchSemaphore(value: 0)
    writer.finishWriting { done.signal() }
    done.wait()
    guard writer.status == .completed else { throw writer.error ?? NSError(domain: "fixtures", code: 3) }
    print("wrote \(url.lastPathComponent)")
}

// MARK: - Main

if which == "media" || which == "all" {
    func minute(_ n: Double) -> Date { baseDate.addingTimeInterval(n * 60) }
    // Speech on the timeline at 4.2–7.4, 10.8–13.0 and 18.7–21.9 s with the
    // clips at 3.0 · 9.2 · 14.2 · 17.2: in each clip's own seconds that is
    // Coast 1.2–4.4, Lake 1.6–3.8, Forest 1.5–4.7.
    try writePhoto("Falls", palette: 0, date: minute(4))
    try writeVideo("Coast", seconds: 6.2, palette: 1, date: minute(3),
                   sound: try clipSound(seconds: 6.2, voice: 1.2...4.4, text: "The road follows the coast all the way to the lighthouse."))
    try writeVideo("Lake", seconds: 5.0, palette: 2, date: minute(2),
                   sound: try clipSound(seconds: 5.0, voice: 1.6...3.8, text: "The lake was perfectly still this morning."))
    try writePhoto("Night", palette: 3, date: minute(1))
    try writeVideo("Forest", seconds: 6.8, palette: 4, date: minute(0),
                   sound: try clipSound(seconds: 6.8, voice: 1.5...4.7, text: "We walked through the forest until the light was gone."))
}
if which == "music" || which == "all" {
    try writeAudio("MorningDrive", samples: clickTrack(bpm: 96, seconds: 60))
    try writeAudio("Sine440", samples: sine(440, seconds: 30, dbfs: -12))
    try writeAudio("LongTrack", samples: clickTrack(bpm: 112, seconds: 204))
    var generator = SystemRandomNumberGenerator()
    try writeAudio("Noise", samples: (0..<Int(30 * audioRate)).map { _ in Float.random(in: -0.3...0.3, using: &generator) })
}

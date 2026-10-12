import AVFoundation
import Foundation
import Testing
@testable import ReMap

@Suite("Realtime audio decoding")
struct VoiceTests {
    @Test("PCM little-endian signed samples retain polarity and range")
    func pcmSamples() throws {
        let format = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false))
        let data = Data([0x00, 0x80, 0x00, 0x00, 0xff, 0x7f, 0x00, 0x40])
        let buffer = try #require(RealtimePCM.decode(data, format: format))
        let samples = try #require(buffer.floatChannelData?[0])
        #expect(buffer.frameLength == 4)
        #expect(samples[0] == -1)
        #expect(samples[1] == 0)
        #expect(abs(samples[2] - 0.9999695) < 0.000001)
        #expect(samples[3] == 0.5)
    }

    @Test("Malformed or incompatible PCM cannot reach the player")
    func invalidPCM() throws {
        let mono = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false))
        let stereo = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 2, interleaved: false))
        #expect(RealtimePCM.decode(Data(), format: mono) == nil)
        #expect(RealtimePCM.decode(Data([0]), format: mono) == nil)
        #expect(RealtimePCM.decode(Data(repeating: 0, count: 262146), format: mono) == nil)
        #expect(RealtimePCM.decode(Data([0, 0]), format: stereo) == nil)
    }
}

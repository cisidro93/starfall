import Foundation
import AVFoundation

@MainActor
final class CockpitAudioManager: ObservableObject {
    static let shared = CockpitAudioManager()

    @Published var isMuted: Bool = false

    private var laserPlayers: [AVAudioPlayer] = []
    private var cannonPlayers: [AVAudioPlayer] = []
    private var lockPlayer: AVAudioPlayer?
    private var scoopPlayer: AVAudioPlayer?
    private var boostPlayer: AVAudioPlayer?
    private var fsdChargePlayer: AVAudioPlayer?
    private var hyperspaceBoomPlayer: AVAudioPlayer?
    private var shieldHitPlayer: AVAudioPlayer?
    private var explosionPlayer: AVAudioPlayer?
    private var ambientDronePlayer: AVAudioPlayer?

    private var laserPoolIndex: Int = 0
    private var cannonPoolIndex: Int = 0
    private var lastLaserPlayTime: TimeInterval = 0.0
    private var lastShieldHitPlayTime: TimeInterval = 0.0

    private init() {
        configureAudioSession()
        buildSynthesizedSoundBank()
        ambientDronePlayer?.play()
    }

    func toggleMute() {
        isMuted.toggle()
        if isMuted {
            ambientDronePlayer?.pause()
        } else {
            ambientDronePlayer?.play()
        }
    }

    func playLaserPulse() {
        guard !isMuted, !laserPlayers.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastLaserPlayTime >= 0.13 else { return }
        lastLaserPlayTime = now

        let player = laserPlayers[laserPoolIndex % laserPlayers.count]
        laserPoolIndex += 1
        player.currentTime = 0
        player.play()
    }

    func playCannonBurst() {
        guard !isMuted, !cannonPlayers.isEmpty else { return }
        let player = cannonPlayers[cannonPoolIndex % cannonPlayers.count]
        cannonPoolIndex += 1
        player.currentTime = 0
        player.play()
    }

    func playTargetLock() {
        guard !isMuted else { return }
        lockPlayer?.currentTime = 0
        lockPlayer?.play()
    }

    func playTractorScoop() {
        guard !isMuted else { return }
        scoopPlayer?.currentTime = 0
        scoopPlayer?.play()
    }

    func playBoostSurge() {
        guard !isMuted else { return }
        boostPlayer?.currentTime = 0
        boostPlayer?.play()
    }

    func playFSDCharge() {
        guard !isMuted else { return }
        fsdChargePlayer?.currentTime = 0
        fsdChargePlayer?.play()
    }

    func playHyperspaceBoom() {
        guard !isMuted else { return }
        hyperspaceBoomPlayer?.currentTime = 0
        hyperspaceBoomPlayer?.play()
    }

    func playShieldHit() {
        guard !isMuted else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastShieldHitPlayTime >= 0.22 else { return }
        lastShieldHitPlayTime = now
        shieldHitPlayer?.currentTime = 0
        shieldHitPlayer?.play()
    }

    func playExplosion() {
        guard !isMuted else { return }
        explosionPlayer?.currentTime = 0
        explosionPlayer?.play()
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func buildSynthesizedSoundBank() {
        // 1. Pulse Laser: crisp downward frequency sweep (880 Hz -> 220 Hz)
        let laserData = Self.makeWAVData(duration: 0.11, volume: 0.26) { t, dur in
            let progress = t / dur
            let freq = 880.0 - 660.0 * progress
            let env = (1.0 - progress) * (1.0 - progress)
            return sin(2.0 * .pi * freq * t) * env
        }
        for _ in 0..<3 {
            if let p = try? AVAudioPlayer(data: laserData) {
                p.prepareToPlay()
                laserPlayers.append(p)
            }
        }

        // 2. Multi-Cannon: punchy kinetic thud (190 Hz -> 65 Hz + harmonic)
        let cannonData = Self.makeWAVData(duration: 0.08, volume: 0.30) { t, dur in
            let progress = t / dur
            let freq = 190.0 - 125.0 * progress
            let env = (1.0 - progress)
            let wave = sin(2.0 * .pi * freq * t) + 0.45 * sin(2.0 * .pi * (freq * 2.7) * t)
            return (wave / 1.45) * env
        }
        for _ in 0..<3 {
            if let p = try? AVAudioPlayer(data: cannonData) {
                p.prepareToPlay()
                cannonPlayers.append(p)
            }
        }

        // 3. Target Lock: classic two-tone cockpit radar chirp (1040 Hz -> 1480 Hz)
        let lockData = Self.makeWAVData(duration: 0.14, volume: 0.24) { t, dur in
            let freq = t < (dur * 0.5) ? 1_040.0 : 1_480.0
            let env = 1.0 - (t / dur) * 0.5
            return sin(2.0 * .pi * freq * t) * env
        }
        lockPlayer = try? AVAudioPlayer(data: lockData)
        lockPlayer?.prepareToPlay()

        // 4. Tractor Scoop Chime: ascending crystalline triad (587 Hz -> 880 Hz -> 1174 Hz)
        let scoopData = Self.makeWAVData(duration: 0.28, volume: 0.28) { t, dur in
            let third = dur / 3.0
            let freq: Double
            if t < third {
                freq = 587.33
            } else if t < third * 2.0 {
                freq = 880.0
            } else {
                freq = 1_174.66
            }
            let env = 1.0 - (t / dur) * 0.65
            return sin(2.0 * .pi * freq * t) * env
        }
        scoopPlayer = try? AVAudioPlayer(data: scoopData)
        scoopPlayer?.prepareToPlay()

        // 5. Boost Surge: deep turbine ramp (95 Hz -> 260 Hz)
        let boostData = Self.makeWAVData(duration: 0.45, volume: 0.32) { t, dur in
            let p = t / dur
            let freq = 95.0 + 165.0 * sin(p * .pi * 0.8)
            let env = sin(p * .pi)
            let wave = sin(2.0 * .pi * freq * t) + 0.5 * sin(2.0 * .pi * (freq * 1.5) * t)
            return (wave / 1.5) * env
        }
        boostPlayer = try? AVAudioPlayer(data: boostData)
        boostPlayer?.prepareToPlay()

        // 6. FSD Charge: rising harmonic Witch-Space spool chord
        let fsdData = Self.makeWAVData(duration: 0.70, volume: 0.28) { t, dur in
            let p = t / dur
            let baseFreq = 140.0 + 320.0 * (p * p)
            let env = sin(p * .pi)
            let w1 = sin(2.0 * .pi * baseFreq * t)
            let w2 = sin(2.0 * .pi * (baseFreq * 1.498) * t)
            return ((w1 + w2) * 0.5) * env
        }
        fsdChargePlayer = try? AVAudioPlayer(data: fsdData)
        fsdChargePlayer?.prepareToPlay()

        // 7. Hyperspace Arrival Boom: deep sub-bass drop (160 Hz -> 48 Hz)
        let boomData = Self.makeWAVData(duration: 0.55, volume: 0.36) { t, dur in
            let p = t / dur
            let freq = 160.0 - 112.0 * sqrt(p)
            let env = 1.0 - p
            return sin(2.0 * .pi * freq * t) * env
        }
        hyperspaceBoomPlayer = try? AVAudioPlayer(data: boomData)
        hyperspaceBoomPlayer?.prepareToPlay()

        // 8. Shield Hit Crackle: electric FM modulation
        let hitData = Self.makeWAVData(duration: 0.16, volume: 0.28) { t, dur in
            let p = t / dur
            let mod = sin(2.0 * .pi * 65.0 * t) * 180.0
            let env = 1.0 - p
            return sin(2.0 * .pi * (420.0 + mod) * t) * env
        }
        shieldHitPlayer = try? AVAudioPlayer(data: hitData)
        shieldHitPlayer?.prepareToPlay()

        // 9. Target Explosion Rumble
        let expData = Self.makeWAVData(duration: 0.50, volume: 0.38) { t, dur in
            let p = t / dur
            let env = (1.0 - p) * (1.0 - p)
            let rumble = sin(2.0 * .pi * (75.0 - 35.0 * p) * t)
            let grit = sin(2.0 * .pi * (210.0 - 130.0 * p) * t) * 0.45
            return ((rumble + grit) / 1.45) * env
        }
        explosionPlayer = try? AVAudioPlayer(data: expData)
        explosionPlayer?.prepareToPlay()

        // 10. Seamless Deep-Space Cockpit & Fusion Thruster Ambient Pad Loop (4.0s exact integer cycles)
        let ambientData = Self.makeWAVData(duration: 4.0, volume: 0.085) { t, _ in
            let sub = sin(2.0 * .pi * 55.0 * t) * 0.50
            let fifth = sin(2.0 * .pi * 82.5 * t) * 0.30
            let octave = sin(2.0 * .pi * 110.0 * t) * 0.20
            let slowPulse = 0.78 + 0.22 * sin(2.0 * .pi * 0.25 * t)
            return (sub + fifth + octave) * slowPulse
        }
        ambientDronePlayer = try? AVAudioPlayer(data: ambientData)
        ambientDronePlayer?.numberOfLoops = -1
        ambientDronePlayer?.prepareToPlay()
    }

    private static func makeWAVData(
        sampleRate: Int = 22_050,
        duration: Double,
        volume: Double,
        generator: (Double, Double) -> Double
    ) -> Data {
        let numSamples = max(1, Int(Double(sampleRate) * duration))
        let dataByteCount = numSamples * 2
        let totalFileBytes = 36 + dataByteCount

        var data = Data(capacity: 44 + dataByteCount)

        func appendASCII(_ str: String) {
            data.append(contentsOf: str.utf8)
        }
        func appendUInt32(_ val: UInt32) {
            var le = val.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ val: UInt16) {
            var le = val.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }
        func appendInt16(_ val: Int16) {
            var le = val.littleEndian
            withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(UInt32(totalFileBytes))
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1) // PCM
        appendUInt16(1) // Mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2))
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(UInt32(dataByteCount))

        let invRate = 1.0 / Double(sampleRate)
        for i in 0..<numSamples {
            let t = Double(i) * invRate
            let raw = generator(t, duration) * volume
            let clamped = min(1.0, max(-1.0, raw))
            let sample = Int16(clamped * 32_760.0)
            appendInt16(sample)
        }

        return data
    }
}

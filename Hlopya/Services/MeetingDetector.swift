import Foundation
import CoreAudio
import AppKit
import Darwin

/// Detects when a video call has likely started by watching which apps are
/// using the microphone, and surfaces a "Record this call?" prompt.
///
/// Mechanism: Core Audio process objects (macOS 14.4+) — the SAME API family
/// `AudioCaptureService` already uses for process taps. Reading the process list
/// needs NO special permission (unlike creating a tap):
///   - `kAudioHardwarePropertyProcessObjectList` → all audio process objects
///   - per object: `kAudioProcessPropertyIsRunningInput` (mic in use?) +
///     `kAudioProcessPropertyPID` → pid → `NSRunningApplication` → bundle id.
///
/// Noise control: a candidate app must hold the mic continuously for
/// `sustainThreshold` seconds (filters short dictation bursts), and apps on the
/// user's blacklist never trigger (add dictation apps there).
@MainActor
final class MeetingDetector {

    struct DetectedApp: Equatable {
        let bundleId: String
        let name: String
    }

    /// Fired once when a likely call is detected.
    var onCallDetected: ((DetectedApp) -> Void)?

    /// Supplied by the owner so we never prompt while Hlopya is already recording.
    var isRecordingProvider: () -> Bool = { false }

    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0
    /// Continuous mic-hold required before prompting — filters dictation bursts.
    private let sustainThreshold: TimeInterval = 8.0

    /// bundleId → first time we saw it continuously holding the mic.
    private var candidateSince: [String: Date] = [:]
    /// Apps already prompted during the current mic session — don't nag twice.
    private var alreadyPrompted: Set<String> = []

    private let selfBundleId = Bundle.main.bundleIdentifier ?? "com.vadims.hlopya"

    // MARK: - Lifecycle

    func start() {
        stop()
        NSLog("[MeetingDetector] started (poll %.0fs, sustain %.0fs)", pollInterval, sustainThreshold)
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        candidateSince.removeAll()
        alreadyPrompted.removeAll()
    }

    // MARK: - Poll loop

    private func tick() {
        // Respect the user toggle (defaults seeded true in HlopyaApp).
        guard UserDefaults.standard.bool(forKey: "autoPromptCalls") else { return }

        // Never prompt over our own recording.
        guard !isRecordingProvider() else {
            candidateSince.removeAll()
            return
        }

        let micApps = appsUsingMicrophone()
        let allMicIds = Set(micApps.map(\.bundleId))
        let blacklist = Self.blacklistedBundleIds()

        // Candidates = mic users that are neither us nor blacklisted.
        let candidates = micApps.filter { $0.bundleId != selfBundleId && !blacklist.contains($0.bundleId) }
        let candidateIds = Set(candidates.map(\.bundleId))

        // Forget debounce state for apps that stopped using the mic.
        candidateSince = candidateSince.filter { candidateIds.contains($0.key) }
        // Allow re-prompting once an app fully releases the mic.
        alreadyPrompted = alreadyPrompted.filter { allMicIds.contains($0) }

        let now = Date()
        for app in candidates where !alreadyPrompted.contains(app.bundleId) {
            let since = candidateSince[app.bundleId] ?? now
            candidateSince[app.bundleId] = since
            if now.timeIntervalSince(since) >= sustainThreshold {
                alreadyPrompted.insert(app.bundleId)
                NSLog("[MeetingDetector] call candidate: %@ (%@)", app.name, app.bundleId)
                onCallDetected?(app)
                break // one prompt at a time
            }
        }
    }

    // MARK: - Core Audio: who is using the microphone

    private func appsUsingMicrophone() -> [DetectedApp] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize)
        guard err == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var processObjects = [AudioObjectID](repeating: AudioObjectID(kAudioObjectUnknown), count: count)
        err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &dataSize, &processObjects)
        guard err == noErr else { return [] }

        var seen = Set<String>()
        var result: [DetectedApp] = []
        for obj in processObjects {
            guard processIsRunningInput(obj), let pid = processPID(obj) else { continue }
            guard let app = resolveApp(pid: pid) else { continue }
            if seen.insert(app.bundleId).inserted {
                result.append(app)
            }
        }
        return result
    }

    private func processIsRunningInput(_ obj: AudioObjectID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let err = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value)
        return err == noErr && value != 0
    }

    private func processPID(_ obj: AudioObjectID) -> pid_t? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        let err = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &pid)
        guard err == noErr, pid > 0 else { return nil }
        return pid
    }

    // MARK: - pid → user-facing app

    /// Resolve a pid to the owning *application*. Browser calls (Google Meet) run
    /// the mic in a helper process (e.g. "Google Chrome Helper (Audio)") that is
    /// not itself a listed application — so we climb parent pids to the real app.
    private func resolveApp(pid: pid_t) -> DetectedApp? {
        if let app = NSRunningApplication(processIdentifier: pid),
           app.activationPolicy == .regular,
           let bid = app.bundleIdentifier {
            return DetectedApp(bundleId: bid, name: app.localizedName ?? bid)
        }
        return climbToApp(from: pid)
    }

    private func climbToApp(from pid: pid_t, maxDepth: Int = 6) -> DetectedApp? {
        var current = pid
        for _ in 0..<maxDepth {
            guard let ppid = parentPID(of: current), ppid > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: ppid),
               app.activationPolicy == .regular,
               let bid = app.bundleIdentifier {
                return DetectedApp(bundleId: bid, name: app.localizedName ?? bid)
            }
            current = ppid
        }
        return nil
    }

    private func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard rc == 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }

    // MARK: - Blacklist (UserDefaults, seeded with Handy in HlopyaApp)

    static let defaultBlacklist: [String] = []

    static func blacklistedBundleIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "callPromptBlacklist") ?? defaultBlacklist)
    }

    static func addToBlacklist(_ bundleId: String) {
        var list = UserDefaults.standard.stringArray(forKey: "callPromptBlacklist") ?? defaultBlacklist
        guard !list.contains(bundleId) else { return }
        list.append(bundleId)
        UserDefaults.standard.set(list, forKey: "callPromptBlacklist")
        NSLog("[MeetingDetector] blacklisted %@", bundleId)
    }

    static func removeFromBlacklist(_ bundleId: String) {
        var list = UserDefaults.standard.stringArray(forKey: "callPromptBlacklist") ?? defaultBlacklist
        list.removeAll { $0 == bundleId }
        UserDefaults.standard.set(list, forKey: "callPromptBlacklist")
    }
}

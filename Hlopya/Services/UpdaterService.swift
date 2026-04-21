import Combine
import Foundation
import Sparkle
import SwiftUI

/// Sparkle auto-update plumbing. Owns the updater controller, publishes
/// `canCheckForUpdates` so the menu item can enable/disable itself, and
/// injects the feed URL from Info.plist (falls back to the `main` appcast
/// if the key ever goes missing in a build).
@MainActor
final class UpdaterService: NSObject, ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        super.init()
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        controller.updater
            .publisher(for: \.canCheckForUpdates, options: [.initial, .new])
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        if let url = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
           !url.isEmpty {
            return url
        }
        return "https://raw.githubusercontent.com/VCasecnikovs/hlopya/main/appcast.xml"
    }
}

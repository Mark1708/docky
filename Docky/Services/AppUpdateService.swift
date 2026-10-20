//
//  AppUpdateService.swift
//  Docky
//

import Combine
import Foundation
import Sparkle

final class AppUpdateService: ObservableObject {
    static let shared = AppUpdateService()

    @Published private(set) var isAvailable = false
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates = false {
        didSet {
            guard automaticallyChecksForUpdates != oldValue, let updater else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @Published var automaticallyDownloadsUpdates = false {
        didSet {
            guard automaticallyDownloadsUpdates != oldValue, let updater else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    @Published var updateCheckInterval: TimeInterval = 86_400 {
        didSet {
            guard updateCheckInterval != oldValue, let updater else { return }
            updater.updateCheckInterval = updateCheckInterval
        }
    }

    let updaterController: SPUStandardUpdaterController?

    private var updater: SPUUpdater? {
        updaterController?.updater
    }

    private var cancellables = Set<AnyCancellable>()

    private init(bundle: Bundle = .main) {
        guard Self.hasEnabledConfiguration(in: bundle) else {
            updaterController = nil
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        updaterController = controller

        let updater = controller.updater
        _ = updater.clearFeedURLFromUserDefaults()

        do {
            try updater.start()
        } catch {
            return
        }

        isAvailable = true
        canCheckForUpdates = updater.canCheckForUpdates
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        updateCheckInterval = updater.updateCheckInterval

        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] automaticallyChecksForUpdates in
                self?.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            }
            .store(in: &cancellables)

        updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] automaticallyDownloadsUpdates in
                self?.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
            }
            .store(in: &cancellables)

        updater.publisher(for: \.updateCheckInterval)
            .receive(on: RunLoop.main)
            .sink { [weak self] updateCheckInterval in
                self?.updateCheckInterval = updateCheckInterval
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        guard isAvailable else { return }
        updater?.checkForUpdates()
    }

    func checkForUpdatesInBackground() {
        guard isAvailable, automaticallyChecksForUpdates, canCheckForUpdates else { return }
        updater?.checkForUpdatesInBackground()
    }

    private static func hasEnabledConfiguration(in bundle: Bundle) -> Bool {
        let updatesEnabled = (bundle.object(forInfoDictionaryKey: "DockyUpdatesEnabled") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let feedURL = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let publicKey = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return updatesEnabled?.caseInsensitiveCompare("YES") == .orderedSame
            && !(feedURL?.isEmpty ?? true)
            && !(publicKey?.isEmpty ?? true)
    }
}

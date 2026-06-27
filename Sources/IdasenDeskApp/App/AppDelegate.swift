import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installWorkspaceObservers()
        Task { @MainActor in
            AppContainer.model.start()
            if !AppContainer.model.settings.hasCompletedOnboarding {
                OnboardingWindowPresenter.shared.present()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeWorkspaceObservers()
        Task { @MainActor in
            AppContainer.model.stopForLifecycleEvent()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in
            OnboardingWindowPresenter.shared.present()
        }
        return true
    }

    private func installWorkspaceObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppContainer.model.reconnectActiveDesk()
            }
        }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppContainer.model.stopForLifecycleEvent()
            }
        }
    }

    private func removeWorkspaceObservers() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }

        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
            self.sleepObserver = nil
        }
    }
}

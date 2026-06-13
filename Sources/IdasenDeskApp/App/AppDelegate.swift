import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            AppContainer.model.start()
            if !AppContainer.model.settings.hasCompletedOnboarding {
                OnboardingWindowPresenter.shared.present()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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
}


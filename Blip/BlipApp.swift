import SwiftUI

import UserNotifications

/// Shows message banners even while the app is open (unless that chat is on screen, which never notifies).
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }
}

@main
struct BlipApp: App {
    @StateObject private var service = PeerService()
    @Environment(\.scenePhase) private var scenePhase
    private let notificationDelegate = NotificationDelegate()

    init() {
        UserDefaults.standard.register(defaults: [
            Pref.maxMeters: 10.0,
            Pref.showAllBLE: true,
            Pref.showNames: false,
            Pref.keepMedia: false,
            Pref.minFreeGB: 2.0,
            Pref.nickname: "",
            Pref.shareLocation: true,
            Pref.notifyBanner: true,
            Pref.notifySound: true,
            Pref.notifyPreview: true,
            Pref.notifyBadge: true,
        ])
        Theme.applyAppearance()
        UNUserNotificationCenter.current().delegate = notificationDelegate
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(service)
                .environmentObject(service.location)
                .preferredColorScheme(.dark)
                .tint(.white)
                .font(.ui(15))
                .onChange(of: scenePhase) { service.appActive = scenePhase == .active }
        }
    }
}

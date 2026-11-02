import SwiftUI
import UserNotifications

struct SettingsScreen: View {
    @EnvironmentObject private var service: PeerService
    @AppStorage(Pref.nickname) private var nickname = ""
    @AppStorage(Pref.maxMeters) private var maxMeters = 10.0
    @AppStorage(Pref.shareLocation) private var shareLocation = true
    @AppStorage(Pref.notifyBanner) private var notifyBanner = true
    @AppStorage(Pref.notifySound) private var notifySound = true
    @AppStorage(Pref.notifyPreview) private var notifyPreview = true
    @AppStorage(Pref.notifyBadge) private var notifyBadge = true
    @EnvironmentObject private var peerService: PeerService
    @State private var systemAllowed: Bool?
    @AppStorage(Pref.keepMedia) private var keepMedia = false
    @AppStorage(Pref.minFreeGB) private var minFreeGB = 2.0
    @State private var freeGB = Storage.freeGB
    @FocusState private var editingName: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("YOUR NAME") {
                        TextField("ANONYMOUS", text: $nickname)
                            .font(.ui(16))
                            .focused($editingName)
                            .submitLabel(.done)
                            .padding(.horizontal, 12).frame(height: 44)
                            .glass()
                            .onChange(of: nickname) { nickname = String(nickname.prefix(16)) }
                            .onSubmit { service.broadcastNickname() }
                            .onChange(of: editingName) { if !editingName { service.broadcastNickname() } }
                        Text(nickname.trimmingCharacters(in: .whitespaces).isEmpty
                             ? "You appear as: \(Identity.kind) · \(Identity.shortID)"
                             : "You appear as: \(nickname.trimmingCharacters(in: .whitespaces)) (\(Identity.kind))")
                            .font(.ui(13))
                        note("Empty = anonymous. Your name only goes to connected NonNet devices. No IP, no account.")
                    }

                    section("NOTIFICATIONS") {
                        Toggle("SHOW NOTIFICATIONS", isOn: $notifyBanner).font(.ui(13))
                        if notifyBanner {
                            Toggle("SOUND", isOn: $notifySound).font(.ui(13))
                            Toggle("SHOW MESSAGE TEXT", isOn: $notifyPreview).font(.ui(13))
                        }
                        Toggle("RED NUMBER ON APP ICON", isOn: $notifyBadge).font(.ui(13))
                            .onChange(of: notifyBadge) { peerService.refreshBadge() }
                        if systemAllowed == false {
                            Button {
                                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                            } label: {
                                Label("TURN ON IN SYSTEM SETTINGS", systemImage: "bell.badge")
                                    .font(.ui(13))
                                    .frame(maxWidth: .infinity)
                                    .padding(10)
                                    .glass(filled: true, radius: 12)
                            }
                            .buttonStyle(.plain)
                        }
                        note("Off text = banner says only \"New message\". The red number counts unread messages.")
                    }
                    .task {
                        let settings = await UNUserNotificationCenter.current().notificationSettings()
                        systemAllowed = settings.authorizationStatus == .authorized
                    }

                    section("RADAR") {
                        Text("MAX DISTANCE: \(Int(maxMeters)) M").font(.ui(14))
                        Slider(value: $maxMeters, in: 1...30, step: 1)
                        Toggle("SHARE MY LOCATION", isOn: $shareLocation).font(.ui(13))
                        note("Only with connected NonNet devices, so they see where you are. Never online.")
                        note("Bluetooth: ±2–5 m. iPhone ↔ iPhone (11 or newer): centimeter accuracy, with direction.")
                    }

                    section("VIDEO") {
                        Text("360P · MAX 10 S · SILENT").font(.ui(14))
                        note("At 2X you record 20 s and the final video is still 10 s.")
                    }

                    section("STORAGE") {
                        Toggle("KEEP RECEIVED PHOTOS AND VIDEOS", isOn: $keepMedia).font(.ui(13))
                        if keepMedia {
                            Text("ONLY IF \(Int(minFreeGB)) GB STAYS FREE").font(.ui(13))
                            Slider(value: $minFreeGB, in: 1...20, step: 1)
                        }
                        Text(String(format: "FREE NOW: %.1f GB", freeGB)).font(.ui(13))
                        note("1X photos and videos are always deleted once seen.")
                    }

                    VStack(spacing: 6) {
                        Text("NonNet \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .font(.ui(13, .medium))
                            .foregroundStyle(.white.opacity(0.6))
                        (Text("© 2026 ").foregroundStyle(.white.opacity(0.6))
                            + Text("CDAV.").foregroundStyle(.white)
                            + Text("IO").foregroundStyle(Color(red: 1, green: 0xD9 / 255, blue: 0x05 / 255)))
                            .font(.ui(15, .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
                .padding()
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .animation(.smooth(duration: 0.25), value: keepMedia)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(SpaceBackground())
            .navigationTitle("SETTINGS")
            .onAppear { freeGB = Storage.freeGB }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.ui(12))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .glass(filled: true)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 22)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.ui(11)).foregroundStyle(.white.opacity(0.55))
    }
}

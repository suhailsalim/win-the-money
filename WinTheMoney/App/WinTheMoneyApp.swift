import SwiftUI

@main
struct WinTheMoneyApp: App {
    @StateObject private var store = Store()
    @StateObject private var sync = SyncManager()
    @StateObject private var gmail = GmailManager()
    @StateObject private var ai = AIManager()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(sync)
                .environmentObject(gmail)
                .environmentObject(ai)
                .tint(Zen.accentDeep)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                store.autoBackupIfEnabled()
                GmailBackground.schedule()
                StatementBackground.schedule()
            case .active:
                Task { await gmail.backgroundScanIfDue(into: store) }
                Task { await gmail.statementScanIfDue(into: store) }
            default: break
            }
        }
        .backgroundTask(.appRefresh(GmailBackground.id)) {
            await gmail.backgroundScanIfDue(into: store)
            GmailBackground.schedule()
        }
        .backgroundTask(.appRefresh(StatementBackground.id)) {
            await gmail.statementScanIfDue(into: store)
            StatementBackground.schedule()
        }
    }
}

import Foundation
import UserNotifications
import BackgroundTasks
import UIKit
import AniliteKit

/// Schedules local notifications for new episodes of shows the user is watching.
/// Everything is computed on device from AniList's airing schedule; nothing is sent anywhere.
enum AiringReminders {
    static let prefix = "airing-"
    static let refreshTaskId = "app.anilite.ios.refresh"
    /// iOS keeps at most 64 pending requests per app; leave headroom.
    static let maxPending = 48

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    struct Plan: Equatable {
        var id: String
        var mediaId: Int
        var title: String
        var body: String
        var fireDate: Date
    }

    /// Pure planning step, unit tested.
    static func plan(library: Library, language: TitleLanguage, leadMinutes: Int, now: Date = Date()) -> [Plan] {
        let watching = library.all.filter { ($0.status.isActive || $0.status == .planning) && $0.type == .anime }
        var plans: [Plan] = []
        for entry in watching {
            guard let next = entry.media.nextAiringEpisode else { continue }
            let fire = next.date.addingTimeInterval(TimeInterval(leadMinutes * 60))
            guard fire > now else { continue }
            let title = entry.media.displayTitle(language)
            let caughtUp = entry.progress >= next.episode - 1
            let body: String
            if entry.status == .planning {
                body = "Episode \(next.episode) is out. It's on your plan list."
            } else if caughtUp {
                body = "Episode \(next.episode) is out. You're caught up and ready."
            } else {
                body = "Episode \(next.episode) is out. You're \(next.episode - 1 - entry.progress) behind."
            }
            plans.append(Plan(id: "\(prefix)\(entry.mediaId)-\(next.episode)", mediaId: entry.mediaId, title: title, body: body, fireDate: fire))
        }
        return Array(plans.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    static func reschedule(library: Library, language: TitleLanguage, leadMinutes: Int, enabled: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard enabled, await authorizationStatus() == .authorized else { return }
        for plan in plan(library: library, language: language, leadMinutes: leadMinutes) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = "airing"
            content.userInfo = ["mediaId": plan.mediaId]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Routes notification taps into the app.
final class NotificationRelay: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRelay()
    @MainActor var openMedia: (@MainActor (Int) -> Void)?
    @MainActor private var pendingMediaId: Int?

    @MainActor func attach(_ handler: @escaping @MainActor (Int) -> Void) {
        openMedia = handler
        if let id = pendingMediaId {
            pendingMediaId = nil
            handler(id)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let id = response.notification.request.content.userInfo["mediaId"] as? Int else { return }
        await MainActor.run {
            if let open = openMedia { open(id) } else { pendingMediaId = id }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationRelay.shared
        return true
    }
}

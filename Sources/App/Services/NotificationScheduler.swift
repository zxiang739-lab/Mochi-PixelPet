import Foundation
import UserNotifications

/// Local notifications only, and only the ones the player opts into.
///
/// Nothing here is used to keep the pet alive — the pet's life is reconstructed
/// from timestamps when the app opens. A notification is an invitation to come
/// back, never a simulation step.
struct NotificationScheduler {
    static let careReminderID = "mochi.notification.care"

    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    func scheduleCareReminder(for pet: PetState, after interval: TimeInterval = 6 * 3600) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.careReminderID])

        guard let need = pet.stats.mostUrgentNeed else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(pet.name) 在等你"
        content.body = "\(need.displayName)掉到 \(Int(pet.stats[need].value)) 了。"
        content.sound = .default
        content.interruptionLevel = .passive

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(60, interval),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.careReminderID,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func authorizationStatusDescription() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized:  return "已允许"
        case .denied:      return "已拒绝"
        case .notDetermined: return "未询问"
        case .provisional: return "临时允许"
        case .ephemeral:   return "临时"
        @unknown default:  return "未知"
        }
    }
}

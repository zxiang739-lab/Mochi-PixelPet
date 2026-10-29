import SwiftUI

struct DiaryView: View {
    @Environment(PetStore.self) private var store
    @State private var filter: EventCategory?

    private var entries: [DiaryEntry] {
        guard let filter else { return store.diary }
        return store.diary.filter { $0.category == filter }
    }

    private var grouped: [DiaryDayGroup] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.createdAt) }
        return buckets
            .map { DiaryDayGroup(day: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.day > $1.day }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    filterBar

                    if entries.isEmpty {
                        ContentUnavailableView(
                            "还没有记录",
                            systemImage: "book.closed",
                            description: Text("照顾好它，故事会自己长出来。")
                        )
                        .padding(.top, 40)
                    } else {
                        ForEach(grouped) { group in
                            section(for: group.day, entries: group.items)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("日记")
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) { filter = nil }
                    } label: {
                        Text("全部").font(.caption.weight(.medium))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                    }
                    .glassChip(filter == nil)

                    ForEach(usedCategories, id: \.self) { category in
                        Button {
                            withAnimation(.snappy) { filter = category }
                        } label: {
                            Label(category.displayName, systemImage: category.symbolName)
                                .font(.caption.weight(.medium))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                        }
                        .glassChip(filter == category)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var usedCategories: [EventCategory] {
        EventCategory.allCases.filter { category in
            store.diary.contains { $0.category == category }
        }
    }

    private func section(for day: Date, entries: [DiaryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayText(day))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            ForEach(entries) { entry in
                entryCard(entry)
            }
        }
    }

    private func entryCard(_ entry: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: entry.symbolName)
                    .font(.caption)
                    .foregroundStyle(entry.isMilestone ? .orange : .accent)
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(timeText(entry.createdAt))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(entry.body)
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            if !entry.grantedItemIDs.isEmpty || entry.experience > 0 {
                HStack(spacing: 6) {
                    ForEach(entry.grantedItemIDs, id: \.self) { itemID in
                        if let item = ItemCatalog.shared.item(itemID) {
                            Text(item.name)
                                .font(.caption2)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .glassEffect(.panel(tint: .blue, interactive: false), in: .capsule)
                        }
                    }
                    if entry.experience > 0 {
                        Text("+\(entry.experience) EXP")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: 20, padding: 0)
    }

    private func dayText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day())
    }

    private func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

private struct DiaryDayGroup: Identifiable {
    var id: Date { day }
    let day: Date
    let items: [DiaryEntry]
}

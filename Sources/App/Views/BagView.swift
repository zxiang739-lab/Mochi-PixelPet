import SwiftUI

struct BagView: View {
    @Environment(PetStore.self) private var store
    @State private var category: ItemCategory = .food

    private var items: [ItemDefinition] {
        ItemCatalog.shared.items(in: category)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    categoryPicker

                    if category == .background {
                        roomSection
                    }

                    if items.isEmpty {
                        ContentUnavailableView(
                            "这一类还没有东西",
                            systemImage: category.symbolName,
                            description: Text("多陪它出去走走，背包会慢慢满起来。")
                        )
                        .padding(.top, 30)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            ForEach(items) { item in
                                itemCard(item)
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("背包")
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(ItemCategory.allCases) { item in
                        Button {
                            withAnimation(.snappy) { category = item }
                        } label: {
                            Text(item.displayName)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                        }
                        .glassChip(category == item)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 4)
        }
    }

    private var roomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("房间")
                .font(.subheadline.weight(.semibold))
            ForEach(RoomCatalog.shared.rooms) { room in
                Button {
                    store.selectRoom(room.id)
                } label: {
                    HStack(spacing: 12) {
                        Image(room.backgroundSprite)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 64, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(room.name).font(.subheadline.weight(.semibold))
                            Text(room.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                        if store.pet.roomID == room.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.accent)
                        } else if store.pet.level < room.requiredLevel {
                            Text("Lv.\(room.requiredLevel)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .glassPanel(cornerRadius: 18, padding: 0)
                }
                .buttonStyle(.plain)
                .disabled(store.pet.level < room.requiredLevel)
            }
        }
    }

    private func itemCard(_ item: ItemDefinition) -> some View {
        let owned = store.pet.count(of: item.id)
        let unlocked = store.pet.unlockedItemIDs.contains(item.id)
        let levelOK = store.pet.level >= item.requiredLevel
        let usable = owned > 0 || (item.category == .background && unlocked)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: item.category.symbolName)
                    .foregroundStyle(tint(for: item.rarity))
                Spacer()
                if item.category == .food || item.category == .care {
                    Text("×\(owned)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Text(item.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Text(item.rarity.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .glassEffect(.panel(tint: tint(for: item.rarity), interactive: false), in: .capsule)

                Spacer()

                if !levelOK {
                    Text("Lv.\(item.requiredLevel)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else if item.category == .accessory {
                    accessoryButton(item)
                } else if item.category == .food, owned > 0 {
                    Button("喂") { store.feed(item.id) }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.glass)
                } else if !usable {
                    Text(item.source.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .glassPanel(cornerRadius: 20, padding: 0)
        .opacity(usable || unlocked ? 1 : 0.55)
    }

    @ViewBuilder
    private func accessoryButton(_ item: ItemDefinition) -> some View {
        if store.pet.equippedAccessoryID == item.id {
            Button("取下") { store.equip(accessoryID: nil) }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.glass)
        } else if store.pet.unlockedItemIDs.contains(item.id) {
            Button("佩戴") { store.equip(accessoryID: item.id) }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.glass)
        } else {
            Text(item.source.displayName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func tint(for rarity: ItemRarity) -> Color {
        switch rarity {
        case .common:    .secondary
        case .uncommon:  .green
        case .rare:      .blue
        case .legendary: .purple
        }
    }
}

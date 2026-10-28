// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ControlRail.swift
//  claudeBlast
//
//  Home, Back, the keyboard and the caregiver's tools, outside the grid.
//

import SwiftUI

/// One control on the rail.
enum RailItem: String, CaseIterable {
    case home, back, topics, keyboard, search, edit, levels, childMode

    var title: String {
        switch self {
        case .home: "Home"
        case .back: "Back"
        case .topics: "Topics"
        case .keyboard: "Keyboard"
        case .search: "Search"
        case .edit: "Edit"
        case .levels: "Level"
        case .childMode: "Child mode"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .back: "arrowshape.backward.fill"
        case .topics: "star.fill"
        case .keyboard: "keyboard"
        case .search: "magnifyingglass"
        case .edit: "pencil"
        case .levels: "stairs"
        case .childMode: "lock.fill"
        }
    }
}

/// A rail slot: one control, two half-height ones over/under, or nothing.
enum RailSlot: Equatable {
    case one(RailItem)
    case pair(RailItem, RailItem)
    case empty

    var items: [RailItem] {
        switch self {
        case .one(let item): [item]
        case .pair(let a, let b): [a, b]
        case .empty: []
        }
    }
}

/// Which rail a device shows (Mark 2026-10-27).
///
/// Home is the first slot and Keyboard the last on both, so the two controls
/// a child reaches for most are in the same place whoever set the device up.
/// The child's rail is short on purpose: nothing on it changes the board.
enum RailProfile: Equatable {
    case child, caregiver

    /// A patient device always shows the child's rail. A caregiver device
    /// shows the caregiver's until Child mode locks it to the child's, and only
    /// the Admin gate unlocks it.
    static func resolve(role: DeviceRole?, childLock: Bool) -> RailProfile {
        role == .caregiver && !childLock ? .caregiver : .child
    }

    var slots: [RailSlot] {
        switch self {
        case .child:
            [.one(.home), .one(.back), .one(.topics), .empty, .empty, .one(.keyboard)]
        case .caregiver:
            [.one(.home), .one(.back), .pair(.levels, .topics), .pair(.search, .edit),
             .one(.childMode), .one(.keyboard)]
        }
    }

    /// Any slot holding two controls, which the bottom rail makes tall enough
    /// for two touch targets.
    var hasPairs: Bool {
        slots.contains { if case .pair = $0 { true } else { false } }
    }
}

/// The level dial drawn inline in a half slot: − N +.
struct RailLevel {
    let level: Int
    let count: Int
    let step: (Int) -> Void
}

/// The rail itself: a column beside the grid in iPad landscape, a row under
/// it in portrait and on iPhone. The slots are the order a child learns, so
/// a row reads them left to right in the same order the column reads them top
/// to bottom, and a pair stays over/under either way.
///
/// It knows nothing about the sentence: Speak and Clear belong to the tray.
///
/// Long-press on Home opens the caregiver menu, anchored on Home wherever the
/// rail is — the only route into Admin from a working board. Edit opens its
/// own menu off the button the same way: options fly out beside the control
/// rather than a sheet taking over the board.
struct ControlRail<Menu: View, EditMenu: View>: View {
    let slots: [RailSlot]
    /// One slot. Square on a full grid; shorter when a large layout's grid has
    /// fewer rows than the rail has slots.
    let slot: CGSize
    let spacing: CGFloat
    var vertical = true
    let isEnabled: (RailItem) -> Bool
    let action: (RailItem) -> Void
    @Binding var isMenuOpen: Bool
    @ViewBuilder let menu: () -> Menu
    @Binding var isEditMenuOpen: Bool
    @ViewBuilder let editMenu: () -> EditMenu
    var level: RailLevel?

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: spacing))
                              : AnyLayout(HStackLayout(spacing: spacing))
        layout {
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                slotView(slot)
                    .frame(width: self.slot.width, height: self.slot.height)
            }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: RailSlot) -> some View {
        switch slot {
        case .one(let item):
            control(item, half: false)
        case .pair(let top, let bottom):
            VStack(spacing: spacing) {
                control(top, half: true)
                control(bottom, half: true)
            }
        case .empty:
            Color.clear.accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func control(_ item: RailItem, half: Bool) -> some View {
        let side = min(slot.width, slot.height)
        if item == .levels, let level {
            RailLevelControl(level: level, height: half ? (slot.height - spacing) / 2 : slot.height)
        } else if item == .home {
            RailButton(item: item, half: half, slot: side, isEnabled: isEnabled(item),
                       action: {
                           // A tap that ends the long-press must not also go Home
                           // under the menu it just opened.
                           guard !isMenuOpen else { return }
                           action(item)
                       },
                       onLongPress: { isMenuOpen = true })
                .popover(isPresented: $isMenuOpen,
                         arrowEdge: vertical ? .trailing : .bottom) {
                    menu().presentationCompactAdaptation(.popover)
                }
        } else if item == .edit {
            RailButton(item: item, half: half, slot: side, isEnabled: isEnabled(item),
                       action: { isEditMenuOpen = true })
                .popover(isPresented: $isEditMenuOpen,
                         arrowEdge: vertical ? .trailing : .bottom) {
                    editMenu().presentationCompactAdaptation(.popover)
                }
        } else {
            RailButton(item: item, half: half, slot: side, isEnabled: isEnabled(item),
                       action: { action(item) })
        }
    }
}

/// The face every rail control shares: a neutral plate, so it never reads as
/// a word the child can say.
private struct RailButton: View {
    let item: RailItem
    let half: Bool
    let slot: CGFloat
    let isEnabled: Bool
    let action: () -> Void
    var onLongPress: (() -> Void)?

    @State private var isPressed = false

    private var glyph: CGFloat { slot * (half ? 0.2 : 0.3) }
    private var font: CGFloat { max(10, slot * (half ? 0.11 : 0.13)) }

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous)
                .fill(Color.railPlate)
                .overlay {
                    let label = Label(item.title, systemImage: item.systemImage)
                        .font(.system(size: font, weight: .medium))
                        .foregroundStyle(.white)
                    if half {
                        // Side by side: half a slot is too short to stack.
                        label.labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 4)
                    } else {
                        VStack(spacing: slot * 0.06) {
                            Image(systemName: item.systemImage)
                                .font(.system(size: glyph, weight: .semibold))
                            Text(item.title)
                                .font(.system(size: font, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                    }
                }
                .opacity(isEnabled ? 1 : 0.35)
                .scaleEffect(isPressed ? 0.94 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isPressed)
        }
        .buttonStyle(RailPressStyle(isPressed: $isPressed))
        .disabled(!isEnabled && onLongPress == nil)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress?() },
            including: onLongPress == nil ? .subviews : .all
        )
        .accessibilityLabel(item.title)
    }
}

/// − level + in the space of half a slot, so a caregiver steps the board
/// without opening anything.
private struct RailLevelControl: View {
    let level: RailLevel
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            step("minus", by: -1, enabled: level.level > 1)
            Text("\(level.level)")
                .font(.system(size: height * 0.42, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Level \(level.level) of \(level.count)")
            step("plus", by: 1, enabled: level.level < level.count)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.railPlate,
                    in: RoundedRectangle(cornerRadius: TileLayout.cornerRadius, style: .continuous))
    }

    private func step(_ symbol: String, by delta: Int, enabled: Bool) -> some View {
        Button { level.step(level.level + delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: height * 0.32, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(delta < 0 ? "Lower level" : "Raise level")
    }
}

/// Reports the press outward so the scale lives on the view. See
/// `TileView`'s style for why press feedback is a `ButtonStyle`.
private struct RailPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

extension Color {
    /// The rail's plate: a graphite that no word colour uses, in both themes.
    static let railPlate = Color(red: 0.27, green: 0.29, blue: 0.35)
}

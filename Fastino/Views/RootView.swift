//
//  RootView.swift
//  Fastino
//
//  Navigation shell: three tabs — the timer (home), Stats and Settings (§4.1,
//  §4.3). The system tab bar is replaced by the Flame Friend floating white
//  pill, so the switching is done here; each tab still owns its NavigationStack
//  so pushes stay inside their tab (Stats → History).
//
//  All three tabs stay alive behind each other rather than being rebuilt on
//  every switch: otherwise flicking to Settings and back would pop you out of
//  History.
//

import SwiftUI
import SwiftData

enum FlameTab: String, CaseIterable, Identifiable {
    case timer = "Timer"
    case stats = "Stats"
    case settings = "Settings"

    var id: String { rawValue }

    /// Which tab the app opens on. Always Timer in a release build; `-tab stats`
    /// lets the screenshot pass reach the other two, which simctl can't tap.
    static var initial: FlameTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count,
           let tab = FlameTab.allCases.first(where: { $0.rawValue.lowercased() == arguments[index + 1].lowercased() }) {
            return tab
        }
        #endif
        return .timer
    }
}

struct RootView: View {
    /// Read straight from the store rather than passed in: the appearance
    /// override has to sit above everything so every tab — and the window's own
    /// background — picks it up. `nil` (no settings row yet, first launch)
    /// means "follow the system", same as `.system`.
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    @State private var selection: FlameTab = .initial

    private var preferredScheme: ColorScheme? {
        settingsList.first?.appearance.colorScheme
    }

    /// The whole app cools down between fasts, background included.
    private var isResting: Bool { !fasts.contains(where: \.isOpen) }

    var body: some View {
        ZStack(alignment: .bottom) {
            FlameBackground(resting: isResting)

            ZStack {
                tab(.timer) { TimerView() }
                tab(.stats) { StatsView() }
                tab(.settings) { SettingsView() }
            }

            // The bar floats over the screens rather than insetting them, so each
            // one keeps its full-bleed background; they leave room for it with
            // `.flameTabBarClearance()`.
            FlameTabBar(selection: $selection)
                .padding(.bottom, 4)
        }
        .tint(Theme.accentText)
        .preferredColorScheme(preferredScheme)
    }

    /// Keeps every tab mounted; only the selected one is visible and tappable.
    private func tab(_ tab: FlameTab, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack { content() }
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
    }
}

// MARK: - Floating pill tab bar

struct FlameTabBar: View {
    @Binding var selection: FlameTab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 6) {
            ForEach(FlameTab.allCases) { tab in
                let isActive = tab == selection
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.flame(13, isActive ? .extraBold : .bold, relativeTo: .footnote))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isActive ? palette.accentText.color : palette.muted.color)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background {
                            if isActive {
                                Capsule().fill(palette.accentSurface.alpha(colorScheme == .dark ? 0.2 : 1).color)
                            }
                        }
                }
                .buttonStyle(FlamePressStyle())
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(palette.elevated.color, in: .capsule)
        .shadow(color: palette.cardShadow.alpha(colorScheme == .dark ? 0.4 : 0.15).color, radius: 8, y: 4)
        // Three labels side by side in one pill can't follow Dynamic Type all the
        // way up without wrapping off-screen; it stops growing at the first
        // accessibility size and the labels scale down from there.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .animation(.snappy(duration: 0.22), value: selection)
    }
}

extension View {
    /// Room at the bottom of a screen for the floating tab bar. Scaled, because
    /// the bar's own label grows with Dynamic Type and a fixed number would let
    /// it swallow the primary button at the larger sizes.
    func flameTabBarClearance() -> some View {
        modifier(FlameTabBarClearance())
    }
}

private struct FlameTabBarClearance: ViewModifier {
    @ScaledMetric(relativeTo: .footnote) private var clearance: CGFloat = 74

    func body(content: Content) -> some View {
        content.padding(.bottom, clearance)
    }
}

enum FlameLayout {
    static let screenHorizontalPadding: CGFloat = 22
    /// The timer screen is centred and gets a touch more air at the sides.
    static let timerHorizontalPadding: CGFloat = 24
    static let screenTopPadding: CGFloat = 14
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}

//
//  RootView.swift
//  Fastino
//
//  Navigation shell: three tabs — the timer (home), Stats and Settings (§4.1,
//  §4.3). The system tab bar is replaced by the Ember floating pill, so the
//  switching is done here; each tab still owns its NavigationStack so pushes stay
//  inside their tab (Stats → History).
//
//  All three tabs stay alive behind each other rather than being rebuilt on
//  every switch: otherwise flicking to Settings and back would pop you out of
//  History.
//

import SwiftUI
import SwiftData

enum EmberTab: String, CaseIterable, Identifiable {
    case timer = "Timer"
    case stats = "Stats"
    case settings = "Settings"

    var id: String { rawValue }

    /// Which tab the app opens on. Always Timer in a release build; `-tab stats`
    /// lets the screenshot pass reach the other two, which simctl can't tap.
    static var initial: EmberTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-tab"), index + 1 < arguments.count,
           let tab = EmberTab.allCases.first(where: { $0.rawValue.lowercased() == arguments[index + 1].lowercased() }) {
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

    @State private var selection: EmberTab = .initial

    private var preferredScheme: ColorScheme? {
        settingsList.first?.appearance.colorScheme
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            EmberBackground()

            ZStack {
                tab(.timer) { TimerView() }
                tab(.stats) { StatsView() }
                tab(.settings) { SettingsView() }
            }

            // The bar floats over the screens rather than insetting them, so each
            // one keeps its full-bleed background; they leave room for it with
            // `.emberTabBarClearance()`.
            EmberTabBar(selection: $selection)
                .padding(.bottom, 4)
        }
        .tint(Theme.accent)
        .preferredColorScheme(preferredScheme)
    }

    /// Keeps every tab mounted; only the selected one is visible and tappable.
    private func tab(_ tab: EmberTab, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack { content() }
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
    }
}

// MARK: - Floating pill tab bar

struct EmberTabBar: View {
    @Binding var selection: EmberTab
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 6) {
            ForEach(EmberTab.allCases) { tab in
                let isActive = tab == selection
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.ember(13, isActive ? .bold : .semibold, relativeTo: .footnote))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(isActive ? palette.accentText.color : palette.textSecondary.color)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background {
                            if isActive {
                                Capsule().fill(palette.accentChip.alpha(colorScheme == .dark ? 0.18 : 0.12).color)
                            }
                        }
                }
                .buttonStyle(EmberPressStyle())
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        .background(
            (colorScheme == .dark ? palette.cardBackground.alpha(0.06).color : palette.cardBackground.color)
                .shadow(.drop(color: palette.cardShadow.alpha(colorScheme == .dark ? 0 : 0.08).color, radius: 8, y: 4)),
            in: .capsule
        )
        .overlay { Capsule().strokeBorder(palette.cardBorder.color, lineWidth: 1) }
        .background(.ultraThinMaterial, in: .capsule)
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
    func emberTabBarClearance() -> some View {
        modifier(EmberTabBarClearance())
    }
}

private struct EmberTabBarClearance: ViewModifier {
    @ScaledMetric(relativeTo: .footnote) private var clearance: CGFloat = 74

    func body(content: Content) -> some View {
        content.padding(.bottom, clearance)
    }
}

enum EmberLayout {
    static let screenHorizontalPadding: CGFloat = 22
    /// Status-bar clearance from the mocks — these screens have no nav bar.
    static let screenTopPadding: CGFloat = 16
}

#Preview {
    RootView()
        .modelContainer(AppContainer.inMemory())
}

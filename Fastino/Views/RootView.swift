//
//  RootView.swift
//  Fastino
//
//  Navigation shell: four tabs — the timer (home), Stats, History and Settings
//  (§4.1, §4.3). The timer's flame is lit while a fast runs, so the bar doubles
//  as a status light from every screen. The system tab bar is replaced by the Flame Friend floating
//  white pill, so the switching is done here; each tab still owns its
//  NavigationStack so any push stays inside its tab.
//
//  All four tabs stay alive behind each other rather than being rebuilt on
//  every switch, so a tab keeps its scroll position and any sheet it had open
//  when you flick away and back.
//

import SwiftUI
import SwiftData

enum FlameTab: String, CaseIterable, Identifiable {
    case timer = "Timer"
    case stats = "Stats"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    /// The bar shows these rather than the names. Four words in one pill left
    /// each of them too narrow to be legible at anything but the default text
    /// size; a symbol says the same thing in a fixed amount of room. The name
    /// is still there as the accessibility label.
    ///
    /// SF Symbols, not the mascot: these are 20pt chrome, and `FlameMascot` is
    /// a face that needs room to read as one — its eyes would be 2pt here, and
    /// half the time the icon is a flat muted tint, which is the state the
    /// mascot is least itself in.
    ///
    /// The timer's flame **is lit only while a fast is running** — filled while
    /// fasting, outline between fasts. The silhouette is the mascot's, and the
    /// tab earns the one thing a mascot here couldn't do at this size: say
    /// something true at a glance from any screen (§5).
    func symbol(fasting: Bool) -> String {
        switch self {
        case .timer: fasting ? "flame.fill" : "flame"
        case .stats: "chart.bar.fill"
        case .history: "list.bullet"
        case .settings: "gearshape.fill"
        }
    }

    /// Which tab the app opens on. Always Timer in a release build; `-tab stats`
    /// (or `history`, or `settings`) lets the screenshot pass reach the others,
    /// which simctl can't tap.
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

/// DEBUG-only launch flags for the screenshot pass. `simctl` can't tap, so
/// anything behind an interaction is otherwise unreachable on a booted
/// simulator.
enum DebugLaunch {
    /// What the Stats screen's Health panels read from.
    ///
    /// `-fixtureHealth` swaps in `FixtureHealthProvider`, because a simulator's
    /// Health store is empty and `simctl` can't tap the permission sheet, so
    /// the panels are otherwise unlookable-at on a booted simulator.
    /// `-noHealthData` makes that fixture return nothing, which is how the
    /// empty states get looked at. Release builds always get the real one.
    static var healthProvider: any HealthProvider {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-fixtureHealth") || arguments.contains("-noHealthData") {
            return FixtureHealthProvider(
                series: arguments.contains("-noHealthData") ? .empty : nil
            )
        }
        #endif
        return HealthKitProvider.shared
    }

    /// Whether the splash runs. `-noSplash` skips it for the screenshot pass,
    /// which takes its shot moments after `simctl launch` and would otherwise
    /// photograph the splash instead of the screen it asked for.
    static var showsSplash: Bool {
        #if DEBUG
        return !ProcessInfo.processInfo.arguments.contains("-noSplash")
        #else
        return true
        #endif
    }
}

struct RootView: View {
    /// Read straight from the store rather than passed in: the appearance
    /// override has to sit above everything so every tab — and the window's own
    /// background — picks it up. `nil` (no settings row yet, first launch)
    /// means "follow the system", same as `.system`.
    @Query(sort: \AppSettings.updatedAt, order: .reverse) private var settingsList: [AppSettings]
    @Query(sort: \Fast.start, order: .reverse) private var fasts: [Fast]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: FlameTab = .initial
    @State private var reconciler = SyncReconciler()
    /// The splash (§5). Starts up unless the screenshot pass turned it off, and
    /// comes down on a timer rather than on any loading work: the store opens
    /// synchronously, so there is nothing to wait for and it is a piece of
    /// staging, not a progress indicator.
    @State private var showSplash = DebugLaunch.showsSplash

    /// The condition SyncReconciler exists to fix. Watching the count means the
    /// @Query republish that follows a CloudKit merge is the trigger — SwiftData
    /// vends no remote-change callback of its own.
    private var openFastCount: Int { fasts.count(where: \.isOpen) }

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
                tab(.history) { HistoryView() }
                tab(.settings) { SettingsView() }
            }

            // The bar floats over the screens rather than insetting them, so each
            // one keeps its full-bleed background; they leave room for it with
            // `.flameTabBarClearance()`.
            FlameTabBar(selection: $selection, isFasting: !isResting)
                .padding(.bottom, 4)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    // Above the tab bar, which is a sibling rather than a child.
                    .zIndex(1)
                    .task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
                    }
            }
        }
        .tint(Theme.accentText)
        .preferredColorScheme(preferredScheme)
        .onChange(of: openFastCount, initial: true) { _, count in
            reconciler.openFastCountChanged(to: count, context: modelContext)
        }
        // Belt and braces: catches a merge that landed while we were suspended,
        // where the @Query republish may already have happened unobserved.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            reconciler.openFastCountChanged(to: openFastCount, context: modelContext)
        }
        .alert(
            "Fasts merged",
            isPresented: Binding(
                get: { reconciler.notice != nil },
                set: { if !$0 { reconciler.notice = nil } }
            )
        ) {
            Button("OK") { reconciler.notice = nil }
        } message: {
            Text(reconciler.notice ?? "")
        }
    }

    /// Keeps every tab mounted; only the selected one is visible and tappable.
    ///
    /// Mounted means `onAppear` and `task` fire at launch for all four, which
    /// matters for anything that asks the user for something: see
    /// `flameTabIsVisible`.
    private func tab(_ tab: FlameTab, @ViewBuilder content: () -> some View) -> some View {
        NavigationStack { content() }
            .opacity(selection == tab ? 1 : 0)
            .allowsHitTesting(selection == tab)
            .accessibilityHidden(selection != tab)
            .environment(\.flameTabIsVisible, selection == tab)
    }
}

// MARK: - Tab visibility

private struct FlameTabIsVisibleKey: EnvironmentKey {
    /// True by default, so a preview or a sheet that isn't inside the tab shell
    /// behaves as if it were on screen.
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the enclosing tab is the selected one.
    ///
    /// Every tab stays mounted, so `task` and `onAppear` fire for all four the
    /// moment the app launches. Anything that prompts the user — the Health
    /// read on Stats (§4.8) — has to wait for its tab to actually be looked at,
    /// or the app asks for Health access on the splash screen.
    var flameTabIsVisible: Bool {
        get { self[FlameTabIsVisibleKey.self] }
        set { self[FlameTabIsVisibleKey.self] = newValue }
    }
}

// MARK: - Floating pill tab bar

struct FlameTabBar: View {
    @Binding var selection: FlameTab
    /// Lights the timer's flame. Read from the store by `RootView`, so the bar
    /// itself stays a dumb control.
    var isFasting: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = Theme.palette(for: colorScheme)
        HStack(spacing: 6) {
            ForEach(FlameTab.allCases) { tab in
                let isActive = tab == selection
                Button {
                    selection = tab
                } label: {
                    Image(systemName: tab.symbol(fasting: isFasting))
                        // Semibold rather than the app's usual 800: SF Symbols
                        // are already dense at this size, and the fill/no-fill
                        // pair plus the capsule carry the selected state.
                        .font(.system(size: 17, weight: isActive ? .bold : .semibold))
                        .symbolRenderingMode(.monochrome)
                        // Fill and outline are the same flame, so it crossfades
                        // rather than swapping.
                        .contentTransition(.symbolEffect(.replace))
                        .foregroundStyle(isActive ? palette.accentText.color : palette.muted.color)
                        .frame(width: 30, height: 21)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background {
                            if isActive {
                                Capsule().fill(palette.accentSurface.alpha(colorScheme == .dark ? 0.2 : 1).color)
                            }
                        }
                        // Scoped to the one button that changed, not to the bar.
                        // Animating the whole bar put the glass layer inside the
                        // animated subtree, so every switch drove a backdrop
                        // resample for the length of the animation — and dragged
                        // all four glyphs through a symbol-replace transition,
                        // because the weight change was animatable too.
                        .animation(.snappy(duration: 0.22), value: isActive)
                        // Lighting the flame is a state change the user just
                        // caused on another screen; it shouldn't snap. Skipped
                        // under Reduce Motion, like every other cue (§5).
                        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: isFasting)
                }
                .buttonStyle(FlamePressStyle())
                .accessibilityLabel(tab.rawValue)
                // The lit flame is information, not decoration, so it can't be
                // carried by the glyph alone.
                .accessibilityValue(tab == .timer ? (isFasting ? "Fasting" : "Not fasting") : "")
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(6)
        // The glass is a visual effect, not a view, so it hit-tests as if it
        // weren't there: without a shape of its own the bar's padding and the
        // gaps between the glyphs let taps straight through to whatever screen
        // is behind — a history row, most visibly. The old opaque `.background`
        // fill blocked them by accident; this does it on purpose.
        .contentShape(.capsule)
        .background { Capsule().fill(.clear) }
        // System Liquid Glass rather than a hand-rolled stack of material and
        // tint: the bar floats over scrolling content, which is exactly what the
        // effect is for, and it brings the refraction, specular edge and shadow
        // that a `.background` fill can't reproduce. Anything painted *over* the
        // glass — an opaque `elevated` fill, as this had — turns it solid again,
        // so the warm cast is passed to the effect as a tint instead of layered
        // on top of it.
        .glassEffect(
            .regular.tint(palette.elevated.alpha(colorScheme == .dark ? 0.28 : 0.5).color),
            in: .capsule
        )
        // Four glyphs side by side still can't follow Dynamic Type all the way
        // up without the pill running off-screen, so it stops growing at the
        // first accessibility size. The glyphs are fixed-size anyway; this caps
        // the padding around them.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

extension View {
    /// Room at the bottom of a screen for the floating tab bar. Scaled, because
    /// the bar's own padding grows with Dynamic Type and a fixed number would
    /// let it swallow the primary button at the larger sizes.
    func flameTabBarClearance() -> some View {
        modifier(FlameTabBarClearance())
    }
}

extension View {
    /// The same room, as safe area rather than padding — for a `List`, whose
    /// content can't be padded from the inside.
    func flameTabBarSafeArea() -> some View {
        modifier(FlameTabBarSafeArea())
    }
}

private struct FlameTabBarSafeArea: ViewModifier {
    @ScaledMetric(relativeTo: .footnote) private var clearance: CGFloat = 74

    func body(content: Content) -> some View {
        content.safeAreaPadding(.bottom, clearance)
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

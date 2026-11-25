import GuideKit
import SwiftUI

/// The map fills the screen; the tour controls or the story playing now sit at the bottom.
struct RootView: View {
    @Environment(GuideModel.self) private var model
    @State private var showStops = Screenshots.screen == "stops"
    @State private var showSettings = Screenshots.screen == "settings"

    var body: some View {
        ZStack {
            GuideMapView()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showStops) {
            StopsListView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: selectedStop) { stop in
            StopDetailView(stop: stop)
        }
        .fullScreenCover(isPresented: onboarding) {
            OnboardingView()
        }
    }

    private var selectedStop: Binding<Stop?> {
        Binding(
            get: { model.selectedStopID.flatMap { model.tour.stop(id: $0) } },
            set: { model.selectedStopID = $0?.id }
        )
    }

    private var onboarding: Binding<Bool> {
        Binding(
            get: { !model.hasOnboarded && (Screenshots.screen == nil || Screenshots.screen == "welcome") },
            set: { if !$0 { model.hasOnboarded = true } }
        )
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            statusChip
            Spacer()
            CircleButton(symbol: "list.bullet", label: "All stops") { showStops = true }
            CircleButton(symbol: "gearshape.fill", label: "Settings") { showSettings = true }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var statusChip: some View {
        if model.isTouring {
            HStack(spacing: 6) {
                Circle().fill(model.source == .demo ? Color.orange : Color.green).frame(width: 8, height: 8)
                Text(model.source == .demo ? "Demo drive" : "Listening for stops")
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    private var bottomPanel: some View {
        if model.narrator.current != nil {
            NowPlayingCard()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            TourPanel()
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct CircleButton: View {
    var symbol: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

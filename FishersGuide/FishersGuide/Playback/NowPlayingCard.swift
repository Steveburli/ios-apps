import GuideKit
import SwiftUI

/// The story playing now: big, glanceable controls a passenger (or the driver, at a stop)
/// can hit without reading.
struct NowPlayingCard: View {
    @Environment(GuideModel.self) private var model

    var body: some View {
        if let current = model.narrator.current {
            let stop = model.tour.stop(id: current.stopID)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    if let stop {
                        CategoryBadge(category: stop.category, size: 44)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.isTeaser ? "Coming up" : (model.narrator.state == .paused ? "Paused" : "Now playing"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Text(current.title)
                            .font(.title3.weight(.bold))
                            .lineLimit(2)
                        if let stop, !stop.subtitle.isEmpty {
                            Text(stop.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                Text(current.script)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                HStack(spacing: 12) {
                    Button {
                        model.narrator.togglePause()
                    } label: {
                        Label(model.narrator.state == .paused ? "Resume" : "Pause",
                              systemImage: model.narrator.state == .paused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        model.skip()
                    } label: {
                        Label("Skip", systemImage: "forward.end.fill")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.bordered)

                    if let stop {
                        Button {
                            model.selectedStopID = stop.id
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .frame(width: 50, height: 50)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("About \(stop.title)")
                    }
                }
                .font(.headline)

                if let next = model.upNext {
                    Label("Up next: \(next.stop.title)", systemImage: "text.line.first.and.arrowtriangle.forward")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
    }
}

/// Start / stop the tour, with progress, when nothing is playing.
struct TourPanel: View {
    @Environment(GuideModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isTouring {
                touringContent
            } else {
                idleContent
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.tour.title)
                    .font(.title2.weight(.bold))
                Text(model.tour.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(model.heardCount) of \(model.tour.stops.count) stories heard")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            if model.location.isDenied {
                Label("Location is off for Fishers Guide. Turn it on in Settings so stories can play as you drive.",
                      systemImage: "location.slash")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button {
                model.startTour(source: .gps)
            } label: {
                Label("Start Driving Tour", systemImage: "car.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)

            Button {
                model.startTour(source: .demo)
            } label: {
                Label("Try a Demo Drive", systemImage: "play.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.bordered)
        }
    }

    private var touringContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.source == .demo ? "Demo drive" : "Tour is on")
                        .font(.headline)
                    Text(model.source == .demo
                         ? "A pretend car is driving the route so you can hear how it works."
                         : "Put the phone away. Stories play by themselves as you get close.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if model.source == .demo {
                ProgressView(value: model.demoRouteProgress)
            }
            HStack(spacing: 12) {
                if model.source == .demo {
                    Button {
                        model.skipDemoAhead()
                    } label: {
                        Label("Next Stop", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button(role: .destructive) {
                    model.stopTour()
                } label: {
                    Label("End Tour", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
            }
            .font(.headline)
        }
    }
}

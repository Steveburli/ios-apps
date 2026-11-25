import GuideKit
import MapKit
import SwiftUI

/// The tour map: every stop as a pin (gray once heard), its trigger circle, you, and the
/// demo route while a demo drive is running.
struct GuideMapView: View {
    @Environment(GuideModel.self) private var model
    @State private var position: MapCameraPosition = .automatic
    @State private var didFrame = false

    var body: some View {
        Map(position: $position) {
            if model.isTouring && model.source == .demo {
                MapPolyline(coordinates: model.tour.demoRoute.map(\.coordinate))
                    .stroke(Color.accentColor.opacity(0.45), lineWidth: 5)
            } else {
                UserAnnotation()
            }

            ForEach(model.pointsOfInterest) { stop in
                MapCircle(center: stop.coordinate, radius: stop.radius)
                    .foregroundStyle(stop.category.color.opacity(0.10))
                    .stroke(stop.category.color.opacity(0.35), lineWidth: 1)
                Annotation(stop.title, coordinate: stop.coordinate, anchor: .center) {
                    Button {
                        model.selectedStopID = stop.id
                    } label: {
                        CategoryBadge(category: stop.category, size: 34, dimmed: model.hasHeard(stop.id))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(stop.title)\(model.hasHeard(stop.id) ? ", heard" : "")")
                }
            }

            if model.isTouring && model.source == .demo, let fix = model.lastFix {
                Annotation("Demo car", coordinate: fix.point.coordinate, anchor: .center) {
                    DemoCar(course: fix.course ?? 0)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onAppear(perform: frameTour)
        .onChange(of: model.lastFix) { _, fix in
            guard model.isTouring, model.source == .demo, let fix else { return }
            withAnimation(.linear(duration: 1)) {
                position = .camera(MapCamera(centerCoordinate: fix.point.coordinate, distance: 5000,
                                             heading: fix.course ?? 0, pitch: 40))
            }
        }
        .onChange(of: model.isTouring) { _, touring in
            if touring && model.source == .gps {
                position = .userLocation(followsHeading: true, fallback: tourRegion)
            } else if !touring {
                withAnimation { position = tourRegion }
            }
        }
    }

    private var tourRegion: MapCameraPosition {
        .region(MKCoordinateRegion(center: model.tour.center.coordinate,
                                   span: MKCoordinateSpan(latitudeDelta: model.tour.span,
                                                          longitudeDelta: model.tour.span)))
    }

    private func frameTour() {
        guard !didFrame else { return }
        didFrame = true
        if model.isTouring, model.source == .demo, let fix = model.lastFix {
            position = .camera(MapCamera(centerCoordinate: fix.point.coordinate, distance: 5000,
                                         heading: fix.course ?? 0, pitch: 40))
        } else {
            position = tourRegion
        }
    }
}

/// The arrow that stands in for you on a demo drive.
private struct DemoCar: View {
    var course: Double

    var body: some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .rotationEffect(.degrees(course))
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(radius: 3)
    }
}

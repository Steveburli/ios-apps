import SwiftUI
import UIKit
import VisionKit
import DoThisNowKit

/// The camera, full screen. To turn the alarm off, it waits for one of your
/// codes (with the alarm sound playing while the alarm is ringing). To add a
/// code, it saves the first one it sees.
struct ScanView: View {
    @Environment(AppModel.self) private var model
    let mode: AppModel.ScanMode
    @State private var message: String?
    @State private var found: String?
    @State private var name = ""
    @State private var holdStart: Date?

    private var ringing: Bool {
        mode == .stopAlarm && (model.engine.ringingAlarm() != nil || WakeAlarms.isTesting)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if CodeScanner.isSupported {
                CodeScanner(paused: found != nil) { payload in handle(payload) }
                    .ignoresSafeArea()
            } else {
                Text("This iPhone’s camera can’t scan codes here.")
                    .foregroundStyle(.white)
                    .padding()
            }
            VStack(spacing: 14) {
                header
                Spacer()
                if mode == .addCode, found != nil {
                    nameCard
                } else {
                    if let message {
                        Text(message)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    if mode == .stopAlarm {
                        escapeHatch
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if ringing { Sounds.startAlarm() }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            Sounds.stopAlarm()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .addCode ? "Scan a code to use" : ringing ? "Good morning!" : "Turn off the next alarm")
                    .font(Theme.display(28))
                Text(mode == .addCode
                     ? "Point at a barcode or QR code that stays away from your bed."
                     : "Scan \(model.state.wake.alarm.codes.map(\.name).joined(separator: " or ")) to turn the alarm off.")
                    .font(.subheadline)
            }
            .foregroundStyle(.white)
            .shadow(radius: 4)
            Spacer()
            if mode == .addCode || !ringing {
                Button {
                    model.scanMode = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .accessibilityLabel("Close")
            }
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Got it. What is it?")
                .font(.headline)
                .foregroundStyle(Theme.ink)
            TextField("e.g. Toothpaste", text: $name)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Scan again") {
                    found = nil
                    name = ""
                }
                .buttonStyle(.dtn(size: .small))
                Spacer()
                Button("Save") {
                    if let found { model.addCode(name: name, payload: found) }
                    model.scanMode = nil
                }
                .buttonStyle(.dtn(.primary, size: .small))
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// For the morning the code is lost or the camera won't work: hold for
    /// 30 seconds, long enough to be awake by the end.
    private var escapeHatch: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let progress = holdStart.map { min(1, context.date.timeIntervalSince($0) / 30) } ?? 0
            Text(progress > 0 ? "Keep holding… \(Int(30 - progress * 30)) s" : "Can’t scan? Hold here for 30 seconds")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule().fill(Theme.accent).frame(width: geo.size.width * progress)
                    }
                }
                .background(.white.opacity(0.18), in: Capsule())
                .clipShape(Capsule())
                .onLongPressGesture(minimumDuration: 30, maximumDistance: 60) {
                    holdStart = nil
                    model.stopAlarm()
                } onPressingChanged: { pressing in
                    holdStart = pressing ? Date() : nil
                }
                .accessibilityLabel("Can’t scan? Touch and hold for 30 seconds to turn the alarm off")
        }
    }

    private func handle(_ payload: String) {
        switch mode {
        case .addCode:
            guard found == nil else { return }
            found = payload
            name = payload.hasPrefix(QRCode.prefix) ? "Printed QR code" : ""
        case .stopAlarm:
            if !model.scanned(payload) {
                message = "That’s not one of your codes"
            }
        }
    }
}

/// VisionKit's live barcode scanner, reporting each new code it sees.
private struct CodeScanner: UIViewControllerRepresentable {
    var paused: Bool
    let onCode: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
                                                recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
                                                isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if paused {
            if scanner.isScanning { scanner.stopScanning() }
        } else if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var last: (payload: String, at: Date)?

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, !payload.isEmpty else { continue }
                // The same code seen again within two seconds is the same scan.
                if let last, last.payload == payload, Date().timeIntervalSince(last.at) < 2 { continue }
                last = (payload, Date())
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onCode(payload)
            }
        }
    }
}

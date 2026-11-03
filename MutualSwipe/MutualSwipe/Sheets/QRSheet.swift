import SwiftUI
import CoreImage.CIFilterBuiltins
import MutualKit

/// A big QR code for the group's iCloud link, so friends at the same table
/// can join by pointing their Camera at it.
struct QRSheet: View {
    @Environment(CloudStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    let groupID: String

    @State private var url: URL?
    @State private var working = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let group = store.groups[groupID] {
                        Text(group.name)
                            .font(Theme.display(30))
                            .foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.center)
                        if let url {
                            code(for: url)
                        } else {
                            off(group)
                        }
                        if let problem {
                            Text(problem).font(.footnote).foregroundStyle(Vote.never.color).multilineTextAlignment(.center)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Join with a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if store.groups[groupID]?.openToAnyone == true { await setOpen(true) }
            }
        }
    }

    private func code(for url: URL) -> some View {
        VStack(spacing: 16) {
            if let image = Self.qrImage(url.absoluteString) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(maxWidth: 320)
                    .accessibilityLabel("QR code to join the group")
            }
            Text("Scan with the Camera app to join.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Text("If they don’t have Mutual yet, the link sends them to get it first. They need to be signed in to iCloud.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            FlowLayout {
                ShareLink(item: url) {
                    Label("Send the link", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.mutual(.quiet))
                Button("Turn off the code", role: .destructive) {
                    Task { await setOpen(false) }
                }
                .buttonStyle(.mutual(.danger))
                .disabled(working)
            }
        }
    }

    private func off(_ group: SwipeGroup) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "qrcode")
                .font(.system(size: 70))
                .foregroundStyle(Theme.muted)
            Text("Turn on a join code and anyone who scans it, or gets the link, can join “\(group.name)” and swipe. You can turn it off any time, and people you invited stay in.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button(working ? "Setting it up…" : "Turn on the join code") {
                Task { await setOpen(true) }
            }
            .buttonStyle(.mutual(wide: true))
            .disabled(working)
        }
    }

    private func setOpen(_ open: Bool) async {
        working = true
        defer { working = false }
        do {
            let link = try await store.setOpenToAnyone(open, groupID: groupID)
            url = open ? link : nil
            problem = nil
            if !open { session.show("The join code is off") }
        } catch {
            problem = error.localizedDescription
        }
    }

    static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import VisionKit
import AVFoundation
import AniliteKit

// MARK: - My code

/// A QR code someone nearby can scan to open your profile, or your Taste DNA when
/// there's no AniList account behind the library.
struct MyCodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: CodeKind = .profile

    enum CodeKind: String, CaseIterable, Identifiable {
        case profile = "Profile"
        case dna = "Taste DNA"
        var id: String { rawValue }
    }

    private var aniListName: String? {
        switch model.account {
        case .connected(_, let name), .publicProfile(let name): return name
        default: return nil
        }
    }

    private var effectiveKind: CodeKind { aniListName == nil ? .dna : kind }

    private var link: URL? {
        switch effectiveKind {
        case .profile:
            guard let name = aniListName else { return nil }
            var comps = URLComponents()
            comps.scheme = ShareCodec.scheme
            comps.host = "user"
            comps.path = "/" + name
            return comps.url
        case .dna:
            return ShareCodec.link(kind: "dna", code: model.myFingerprint.code)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                if aniListName != nil {
                    Picker("Code", selection: $kind) {
                        ForEach(CodeKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if let link, let image = QRCode.image(for: link.absoluteString) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(18)
                        .background(Theme.textPrimary, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .frame(maxWidth: 280)
                        .accessibilityLabel("QR code for \(effectiveKind == .profile ? "your profile" : "your Taste DNA")")
                        .id(effectiveKind)
                        .transition(.opacity)
                } else {
                    Skeleton(cornerRadius: Theme.corner)
                        .frame(width: 280, height: 280)
                }

                VStack(spacing: 6) {
                    Text(model.account.displayName ?? "You")
                        .font(Typo.display(26))
                        .foregroundStyle(Theme.textPrimary)
                    Text(effectiveKind == .profile
                         ? "Scanning this opens your AniList profile in Anilite, where they can follow you and compare tastes."
                         : "Scanning this adds your Taste DNA to their friends. It carries your taste summary, never your list.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if let link {
                    ShareLink(item: link, subject: Text("Anilite"),
                              message: Text("Open in Anilite to compare our anime tastes.")) {
                        Label("Share link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Theme.gutter)
            .animation(Motion.standard, value: effectiveKind)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ink0)
            .navigationTitle("My code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

enum QRCode {
    private static let context = CIContext()

    /// Ink-on-paper QR image, rendered at one pixel per module so it scales crisply.
    static func image(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = string.utf8.count > 300 ? "L" : "M"
        guard let output = filter.outputImage else { return nil }
        let colored = output.applyingFilter("CIFalseColor", parameters: [
            "inputColor0": CIColor(red: 0.067, green: 0.063, blue: 0.059),
            "inputColor1": CIColor(red: 0.937, green: 0.918, blue: 0.878)
        ])
        guard let cg = context.createCGImage(colored, from: colored.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Scan a code

struct ScanCodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var handled = false
    @State private var scannerAvailable = false
    @State private var checkedCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if scannerAvailable {
                    QRScanner { open($0) }
                        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                .strokeBorder(Theme.ink3, lineWidth: 1)
                        }
                        .frame(maxHeight: 420)
                    Text("Point the camera at an Anilite code.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                } else if !checkedCamera {
                    Skeleton(cornerRadius: Theme.corner)
                        .frame(maxHeight: 420)
                } else {
                    EmptyStateView(symbol: "camera",
                                   title: "Camera unavailable",
                                   message: "Scanning needs camera access. You can turn it on in Settings, or paste a link below.")
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or paste a link")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                    HStack(spacing: 10) {
                        TextField("anilite:// or anilist.co link", text: $pasted)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { open(pasted) }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.ink1, in: RoundedRectangle(cornerRadius: Theme.cornerSmall, style: .continuous))
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first {
                                Task { @MainActor in
                                    pasted = first
                                    open(first)
                                }
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.roundedRectangle(radius: Theme.cornerSmall))
                        .tint(Theme.ink3)
                    }
                }
            }
            .padding(Theme.gutter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ink0)
            .task { await checkCamera() }
            .navigationTitle("Scan a code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }

    private func checkCamera() async {
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        scannerAvailable = DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        checkedCamera = true
    }

    /// Accepts Anilite links and AniList profile links. Closes the sheet first so the
    /// destination (another sheet or a pushed profile) can present cleanly.
    private func open(_ raw: String) {
        guard !handled else { return }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = Self.destination(for: text) else {
            if !text.isEmpty {
                model.showBanner("That isn't an Anilite or AniList link.")
                Haptics.warning()
            }
            return
        }
        handled = true
        Haptics.success()
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            model.handle(url)
        }
    }

    static func destination(for text: String) -> URL? {
        guard let url = URL(string: text) else { return nil }
        if url.scheme == ShareCodec.scheme { return DeepLink.parse(url) == nil ? nil : url }
        // https://anilist.co/user/<name>/ → anilite://user/<name>
        guard let host = url.host?.lowercased(), host.hasSuffix("anilist.co") else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        if parts.count >= 2, parts[0] == "user" {
            var comps = URLComponents()
            comps.scheme = ShareCodec.scheme
            comps.host = "user"
            comps.path = "/" + parts[1]
            return comps.url
        }
        if parts.count >= 2, parts[0] == "anime" || parts[0] == "manga", let id = Int(parts[1]) {
            return URL(string: "\(ShareCodec.scheme)://media/\(id)")
        }
        return nil
    }
}

/// VisionKit's live scanner, limited to QR codes.
private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let payload = code.payloadStringValue {
                    onCode(payload)
                    return
                }
            }
        }
    }
}

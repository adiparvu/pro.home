import SwiftUI

// MARK: - Chat file preview sheet
//
// QuickLook can only preview *local* files, so a remote (Supabase Storage)
// file is downloaded to a temp location first, then handed to the shared
// QuickLookPreview representable (defined in Features/Blueprints).

struct FilePreviewSheet: View {
    let url: URL
    let filename: String
    @Environment(\.dismiss) private var dismiss

    @State private var localURL: URL?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ZStack {
                if let localURL {
                    QuickLookPreview(url: localURL)
                        .ignoresSafeArea(edges: .bottom)
                } else if failed {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Couldn't open this file")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        Link("Open in browser", destination: url)
                            .font(.system(size: 14, weight: .medium))
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await download() }
        }
    }

    private func download() async {
        guard localURL == nil else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let dir = FileManager.default.temporaryDirectory
            let dest = dir.appendingPathComponent(filename.isEmpty ? url.lastPathComponent : filename)
            try data.write(to: dest, options: .atomic)
            localURL = dest
        } catch {
            failed = true
        }
    }
}

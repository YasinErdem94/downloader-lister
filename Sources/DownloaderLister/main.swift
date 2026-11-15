import SwiftUI
import AppKit

@main
struct DownloaderListerApp: App {
    var body: some Scene { WindowGroup("DownloaderLister") { ContentView() }.windowStyle(.automatic) }
}

struct DownloadItem: Identifiable, Hashable {
    let id = UUID(); var title: String; var url: String; var status = "Bekliyor"; var progress: Double = 0
}

@MainActor final class DownloadViewModel: ObservableObject {
    @Published var input = ""
    @Published var items: [DownloadItem] = []
    @Published var selected = Set<UUID>()
    @Published var destination = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first!.appendingPathComponent("YouTube Downloads")
    @Published var quality = "320 kbps"
    @Published var browser = "Yok"
    @Published var inputMode = "Satır satır link"
    @Published var isBusy = false
    @Published var message = "Hazır"
    @Published var showConflictPrompt = false
    @Published var conflictMode = "ask"
    private var processes: [Process] = []

    func addInput() {
        let parts: [String]
        if inputMode == "Satır satır link" { parts = input.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init) }
        else { parts = extractURLs(input) }
        let urls = parts.filter { $0.contains("youtube.com") || $0.contains("youtu.be") }
        for url in urls where !items.contains(where: { $0.url == url }) { items.append(DownloadItem(title: "Video bilgisi alınacak", url: url)) }
        selected.formUnion(items.suffix(urls.count).map(\.id)); input = ""
        message = urls.isEmpty ? "Geçerli YouTube linki bulunamadı" : "\(urls.count) öğe kuyruğa eklendi"
        Task { await expandPlaylists(urls) }
    }

    private func expandPlaylists(_ urls: [String]) async {
        for url in urls where url.contains("list=") {
            let result = await runTool([url, "--flat-playlist", "--print", "%(title)s\t%(webpage_url)s"])
            let parsed = result.split(separator: "\n").compactMap { line -> DownloadItem? in
                let p = line.split(separator: "\t", maxSplits: 1).map(String.init)
                guard p.count == 2 else { return nil }
                return DownloadItem(title: p[0], url: p[1])
            }
            if !parsed.isEmpty {
                items.removeAll { $0.url == url }
                selected = selected.filter { id in items.contains(where: { $0.id == id }) }
                items.append(contentsOf: parsed); selected.formUnion(parsed.map(\.id))
                message = "Playlist açıldı: \(parsed.count) video"
            }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { destination = url }
    }

    func search() {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines); guard !query.isEmpty else { return }
        message = "YouTube aranıyor…"; input = ""
        Task { let result = await runTool(["ytsearch10:\(query)", "--flat-playlist", "--print", "%(title)s\t%(webpage_url)s"])
            let parsed = result.split(separator: "\n").compactMap { line -> DownloadItem? in let p = line.split(separator: "\t", maxSplits: 1).map(String.init); guard p.count == 2 else { return nil }; return DownloadItem(title: p[0], url: p[1]) }
            items.append(contentsOf: parsed); selected.formUnion(parsed.map(\.id)); message = parsed.isEmpty ? "Sonuç bulunamadı" : "\(parsed.count) sonuç eklendi"
        }
    }

    func fetchTitles() {
        guard !items.isEmpty else { return }; message = "Video bilgileri alınıyor…"
        Task { for index in items.indices { let r = await runTool([items[index].url, "--get-title", "--no-playlist"]); if let title = r.split(separator: "\n").first { items[index].title = String(title) } }; message = "Hazır" }
    }

    func start() {
        guard !isBusy, !selected.isEmpty else { message = "İndirmek için en az bir öğe seçin"; return }
        isBusy = true; message = "İndirme başladı"; try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let chosen = items.filter { selected.contains($0.id) }
        Task { await withTaskGroup(of: Void.self) { group in
            var iterator = chosen.makeIterator()
            for _ in 0..<2 { if let item = iterator.next() { group.addTask { await self.download(item) } } }
            while await group.next() != nil { if let item = iterator.next() { group.addTask { await self.download(item) } } }
        }; isBusy = false; message = "Kuyruk tamamlandı" }
    }

    private func download(_ item: DownloadItem) async {
        await update(item.id, status: "İndiriliyor…", progress: 0.1)
        var args = [item.url, "--no-playlist", "--extract-audio", "--audio-format", "mp3", "--audio-quality", "0", "--embed-metadata", "--embed-thumbnail", "--newline", "--progress", "-o", destination.appendingPathComponent("%(title)s.%(ext)s").path]
        if let ffmpeg = findExecutable("ffmpeg") {
            args += ["--ffmpeg-location", URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path]
        }
        if conflictMode == "skip" { args += ["--no-overwrites", "--continue"] } else if conflictMode == "overwrite" { args += ["--force-overwrites"] }
        if browser != "Yok" { args += ["--cookies-from-browser", browser.lowercased()] }
        let output = await runTool(args, id: item.id)
        if output.contains("ERROR") {
            let detail = output.split(separator: "\n").last.map(String.init) ?? "Bilinmeyen indirme hatası"
            await update(item.id, status: "Hata: \(detail.prefix(90))", progress: 0)
        } else {
            await update(item.id, status: "Tamamlandı", progress: 1)
        }
    }

    private func runTool(_ arguments: [String], id: UUID? = nil) async -> String {
        guard let executable = findExecutable("yt-dlp") else { return "ERROR: yt-dlp bulunamadı" }
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
        if let id { processes.append(p); await update(id, status: "İndiriliyor…", progress: 0.25) }
        do {
            try p.run()
            var output = ""
            while p.isRunning {
                let data = pipe.fileHandleForReading.availableData
                guard !data.isEmpty else { continue }
                let chunk = String(data: data, encoding: .utf8) ?? ""
                output += chunk
                if let id, let match = chunk.range(of: #"(\d{1,3}(?:\.\d+)?)%"#, options: .regularExpression), let value = Double(chunk[match].dropLast()) {
                    await update(id, status: "İndiriliyor %\(Int(value))", progress: min(value / 100, 0.99))
                }
            }
            output += String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            return output
        } catch { return "ERROR: \(error.localizedDescription)" }
    }

    func cancel() { processes.forEach { if $0.isRunning { $0.terminate() } }; processes.removeAll(); isBusy = false; message = "İndirme iptal edildi" }
    func remove(_ offsets: IndexSet) { items.remove(atOffsets: offsets); selected = selected.filter { id in items.contains { $0.id == id } } }
    func removeSelected() { items.removeAll { selected.contains($0.id) }; selected.removeAll() }
    func clearAll() { items.removeAll(); selected.removeAll(); message = "Kuyruk temizlendi" }
    private func update(_ id: UUID, status: String, progress: Double) async { await MainActor.run { if let i = self.items.firstIndex(where: { $0.id == id }) { self.items[i].status = status; self.items[i].progress = progress } } }
    private func findExecutable(_ name: String) -> String? { ["/opt/homebrew/bin/\(name)", "/opt/anaconda3/bin/\(name)", "/usr/local/bin/\(name)", "/usr/bin/\(name)"].first { FileManager.default.isExecutableFile(atPath: $0) } }
    private func extractURLs(_ text: String) -> [String] { text.split { $0.isWhitespace || $0 == "," }.map(String.init).filter { $0.contains("youtube.com") || $0.contains("youtu.be") }.map { $0.trimmingCharacters(in: .punctuationCharacters) } }
}

struct ContentView: View {
    @StateObject private var vm = DownloadViewModel()
    var body: some View {
        VStack(spacing: 0) {
            header
            inputCard
            queueHeader
            queue
            footer
        }
        .frame(minWidth: 860, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) { Text("DownloaderLister").font(.title.bold()); Text("Videolarını MP3 olarak indir").foregroundStyle(.secondary) }
            Spacer()
            Button { vm.chooseFolder() } label: { Label("Kayıt klasörü", systemImage: "folder") }
            Text(vm.destination.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 230, alignment: .trailing)
        }.padding(24).background(.thickMaterial)
    }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Link ekle veya YouTube’da ara").font(.headline)
            HStack {
                Picker("Giriş türü", selection: $vm.inputMode) { Text("Her satır bir link").tag("Satır satır link"); Text("Metinden linkleri ayıkla").tag("Metinden link ayıkla") }.labelsHidden().frame(width: 190)
                TextField("YouTube linki veya arama kelimesi…", text: $vm.input).textFieldStyle(.roundedBorder).onSubmit { vm.addInput() }
                Button("Link ekle", action: vm.addInput).buttonStyle(.borderedProminent)
                Button("Ara", action: vm.search)
            }
            Text("Playlist linki eklediğinde içindeki videolar listeye ayrı ayrı gelir.").font(.caption).foregroundStyle(.secondary)
        }.padding(18).background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor))).padding(.horizontal, 20).padding(.top, 16)
    }

    private var queueHeader: some View {
        HStack {
            Text("2. İndirme listesi").font(.headline)
            Text("\(vm.items.count) video").font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Tümünü seç") { vm.selected = Set(vm.items.map(\.id)) }
            Button("Hiçbirini seçme") { vm.selected.removeAll() }
            Button("Seçilenleri sil") { vm.removeSelected() }.disabled(vm.selected.isEmpty)
            Button("Listeyi temizle") { vm.clearAll() }.disabled(vm.items.isEmpty)
        }.padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 10)
    }

    private var queue: some View {
        Group {
            if vm.items.isEmpty { VStack(spacing: 10) { Image(systemName: "music.note.list").font(.system(size: 38)).foregroundStyle(.secondary); Text("Listen henüz boş").font(.title3); Text("Yukarıdaki alana bir YouTube linki yapıştır.").foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ScrollView { LazyVStack(spacing: 0) { ForEach(vm.items) { item in QueueRow(item: item, isSelected: vm.selected.contains(item.id), toggle: { if vm.selected.contains(item.id) { vm.selected.remove(item.id) } else { vm.selected.insert(item.id) } }, delete: { vm.items.removeAll { $0.id == item.id }; vm.selected.remove(item.id) }) } }.padding(.horizontal, 20) } }
        }
    }

    private var footer: some View {
        HStack {
            Text(vm.message).font(.caption).foregroundStyle(.secondary); Spacer()
            Picker("Çerez", selection: $vm.browser) { Text("Giriş yok").tag("Yok"); Text("Chrome oturumu").tag("Chrome"); Text("Safari oturumu").tag("Safari"); Text("Firefox oturumu").tag("Firefox") }.frame(width: 150)
            Button(vm.isBusy ? "İndiriliyor…" : "3. İndirmeyi başlat") { vm.start() }.buttonStyle(.borderedProminent).disabled(vm.isBusy || vm.selected.isEmpty)
            Button("Durdur") { vm.cancel() }.disabled(!vm.isBusy)
        }.padding(20).background(.thickMaterial)
    }
}

struct QueueRow: View {
    let item: DownloadItem; let isSelected: Bool; let toggle: () -> Void; let delete: () -> Void
    var body: some View { HStack(spacing: 12) { Button(action: toggle) { Image(systemName: isSelected ? "checkmark.square.fill" : "square").font(.title3) }.buttonStyle(.plain); Image(systemName: item.progress == 1 ? "checkmark.circle.fill" : "music.note").foregroundStyle(item.progress == 1 ? .green : .accentColor); VStack(alignment: .leading, spacing: 5) { Text(item.title).lineLimit(1); Text(item.status).font(.caption).foregroundStyle(item.status == "Hata oluştu" ? .red : .secondary); ProgressView(value: item.progress).progressViewStyle(.linear).opacity(item.progress > 0 && item.progress < 1 ? 1 : 0) }.frame(maxWidth: .infinity, alignment: .leading); Button(action: delete) { Image(systemName: "trash").foregroundStyle(.red) }.buttonStyle(.plain) }.padding(.vertical, 12).overlay(alignment: .bottom) { Divider() } }
}

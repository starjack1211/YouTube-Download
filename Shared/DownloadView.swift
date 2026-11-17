import SwiftUI

struct DownloadView: View {
    @StateObject private var downloader = Downloader()
    @AppStorage("maxHeight") private var maxHeight = 1080
    @AppStorage("audioKbps") private var audioKbps = 128
    @State private var link: String
    private let isShare: Bool
    private let close: (() -> Void)?
    init(link: String = "", isShare: Bool = false, close: (() -> Void)? = nil) {
        _link = State(initialValue: link)
        self.isShare = isShare
        self.close = close
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 44)).foregroundStyle(.red)
                        Text("喜歡的影片，留在相簿").font(.title2.bold())
                        Text("下載 MP4，保留原始影音品質。").foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                Section("影片連結") {
                    TextField("https://youtu.be/…", text: $link, axis: .vertical)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().disabled(downloader.busy)
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first { link = value }
                    }.disabled(downloader.busy)
                }
                Section {
                    Picker("畫質上限", selection: $maxHeight) {
                        ForEach([360, 480, 720, 1080, 1440, 2160], id: \.self) { height in
                            Text("\(height)p").tag(height)
                        }
                    }
                    Picker("音質上限", selection: $audioKbps) {
                        Text("節省空間 · 64 kbps").tag(64)
                        Text("標準 · 128 kbps").tag(128)
                        Text("高音質 · 256 kbps").tag(256)
                        Text("最高可用").tag(9999)
                    }
                } header: { Text("下載設定") } footer: {
                    Text("選擇不超過上限的最佳相容格式。音軌未提供指定品質時，使用最低可用音軌並顯示實際品質；不會將低音質升頻。")
                }.disabled(downloader.busy)
                Section {
                    if downloader.busy {
                        ProgressView(value: downloader.progress)
                        Button("取消下載", role: .destructive) { downloader.cancel() }
                    } else {
                        Button { download() } label: {
                            Label("下載到相簿", systemImage: "square.and.arrow.down")
                                .font(.headline).frame(maxWidth: .infinity)
                        }.disabled(YouTubeLink.videoID(in: link) == nil)
                    }
                    Text(downloader.status).font(.callout).textSelection(.enabled)
                    if !downloader.detail.isEmpty {
                        Text(downloader.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    if let output = downloader.output, !downloader.busy {
                        ShareLink(item: output) { Label("分享檔案／儲存到檔案", systemImage: "square.and.arrow.up") }
                        if !downloader.saved {
                            Button("重試儲存到相簿") { downloader.retrySave() }
                        }
                        Button("刪除 App 內副本", role: .destructive) { downloader.removeLocalCopy() }
                    }
                }
                Section {
                    Text(isShare
                         ? "分享入口會依此處記住的設定自動下載。請保持此畫面開啟；長影片可能因 iOS 限制中斷，建議改用主 App 貼上連結。主 App 與分享入口各自記住設定。"
                         : "也可以在 YouTube → 分享 → 更多 →「下載到相簿」開始下載。下載時請保持 App 開啟。副本可在「檔案 → 我的 iPhone → 影片下載 → Downloads」管理。")
                    Text("僅下載你有權下載的內容。不支援需要登入、付費或受保護的影片；YouTube 改版可能使解析暫時失效。")
                }.font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("影片下載")
            .tint(.red)
            .toolbar {
                if let close {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("關閉") { downloader.cancel(); close() }
                    }
                }
            }
            .task {
                if isShare && YouTubeLink.videoID(in: link) != nil { download() }
            }
        }
    }
    private func download() {
        downloader.start(text: link, maxHeight: maxHeight, audioKbps: audioKbps)
    }
}

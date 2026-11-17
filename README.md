# 影片下載 · iPhone

原生 SwiftUI App，iOS 17 以上。無需另架伺服器或安裝 Python。

## 使用

- 在主 App 貼上 YouTube 影片、Shorts 或直播回放連結，選擇畫質及音質後下載到相簿。
- 在 YouTube 點「分享 → 更多 → 下載到相簿」。分享入口會自動開始下載。
- 畫質上限：360p／480p／720p／1080p／1440p／2160p；取不超過上限的最高相容 MP4 格式。
- 音質上限：64／128／256 kbps／最高可用。選擇原始 AAC 音軌，不虛增音質；沒有低於上限的音軌時使用最低可用音軌並告知。
- 合併影音使用 AVFoundation passthrough，不重新壓縮。實際畫質和音質依來源與裝置支援決定。
- 下載進度、取消、相簿儲存失敗重試、分享檔案與刪除 App 內副本。
- 相簿採僅加入權限，不讀取使用者其他照片。

## 取得 IPA，使用 iLoader 安裝

1. 開啟本專案的 **Actions → Build iPhone IPA**，選最新成功的執行。
2. 在 Artifacts 下載 **YouTubeDownload-IPA** 並解壓縮，取得 `YouTubeDownload.ipa`。
3. 使用 iLoader 匯入 IPA，以自己的 Apple ID 簽署安裝。請保留 Share Extension，否則 YouTube 分享選單不會出現下載入口。
4. 首次開啟先貼上連結測試，允許加入相簿。YouTube 分享選單若未出現入口，點更多／編輯啟用。
5. 程式更新後會自動再次打包；也可使用 Run workflow 手動重建。

這是供側載重新簽署的 **unsigned IPA**，不是可直接點擊安裝的 App Store 包。

## 已知限制

- 分享 Extension 受 iOS 記憶體與執行時間限制。請保持畫面開啟；長影片建議貼到主 App。這版未宣稱支援背景下載。
- 為避免側載重簽 App Groups 問題，主 App 與分享入口各自保存畫質／音質設定。分享預設 1080p／128 kbps；下載中可取消後改設定重試。
- 來源只提供 WebM、不相容編碼或超過畫質上限時會報錯；沒有保證每部影片都有 4K 或指定音質。
- 不支援登入、會員、付費、DRM 內容、私人影片、播放清單批次下載或正在進行的直播。
- YouTube 可能隨時更改非官方介面；解析或 HTTP 403 問題可能需要更新依賴後重建。
- 只使用本機解析，不使用第三方遠端解析伺服器，也不收集登入 Cookie。
- 成功輸出會同時保留 App 內副本，可分享或刪除。主 App 的副本位於「檔案 → 我的 iPhone → 影片下載 → Downloads」。分享入口副本位於 Extension 自己的容器，請在關閉前分享或刪除。
- 僅下載你有權下載的內容。

## 開發

使用 Xcode、Homebrew 與 XcodeGen：

```sh
brew install xcodegen
swift test
xcodegen generate
xcodebuild -project YouTubeDownload.xcodeproj -scheme YouTubeDownload \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

程式拆分：
- `Shared/Downloader.swift`：解析、品質選擇、分軌下載、合併、相簿寫入。
- `Shared/DownloadView.swift`：主 App 及分享入口共用介面。
- `Shared/YouTubeLink.swift`：連結驗證。
- `ShareExtension/`：YouTube 分享連結接收。
- `project.yml`：XcodeGen 專案與 Extension。
- `.github/workflows/build-ios.yml`：macOS 虛擬機測試、編譯及 IPA 打包。

使用 [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit)（MIT），固定 revision 以便重現編譯。YouTubeKit 授權亦包含於 App 的「開放原始碼授權」。此專案與 YouTube／Google 無隸屬關係。

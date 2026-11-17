# 影片下載 · iPhone

原生 SwiftUI App，iOS 17 以上。無需另架伺服器或安裝 Python。

## 使用

- 在主 App 貼上 YouTube 影片、Shorts 或直播回放連結，選擇畫質及音質後下載到相簿。
- 在 YouTube 點「分享 → 更多 → 下載到相簿」。分享入口會自動開始下載。
- 畫質上限：360p／480p／720p／1080p／1440p／2160p；取不超過上限的最高相容 MP4 格式。
- 音質上限：64／128／256 kbps／最高可用。選擇原始 AAC 音軌，不虛增音質；沒有低於上限的音軌時使用最低可用音軌並告知。
- 合併影音使用 AVFoundation passthrough，不重新壓縮。實際畫質和音質依來源與裝置支援決定。
- 真實資料量進度、百分比、下載速度與預估剩餘時間；支援取消、相簿儲存失敗重試、分享檔案與刪除 App 內副本。
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
- 只使用本機解析。YouTube 自動核發的匿名工作階段 Cookie 只供 App 的播放請求使用，不讀取外部瀏覽器登入資料。
- 影片的地區限制、YouTube 反機器人驗證或服務異動，可能阻止下載；需要可正常播放該影片的網路與工作階段。
- 成功輸出會同時保留 App 內副本，可分享或刪除。主 App 的副本位於「檔案 → 我的 iPhone → 影片下載 → Downloads」。分享入口副本位於 Extension 自己的容器，請在關閉前分享或刪除。
- 僅下載你有權下載的內容。

## 開發

使用 Xcode、Homebrew 與 XcodeGen：

```sh
brew install xcodegen
python3 Scripts/prepare_vendor.py
swift test
swift test --package-path Integration
python3 Scripts/make_icon.py
xcodegen generate
bash Scripts/test_simulator.sh
xcodebuild -project YouTubeDownload.xcodeproj -scheme YouTubeDownload \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

## 測試與交付條件

| 測試範圍 | 項目數 |
| --- | ---: |
| 連結辨識、進度、速度、剩餘時間 | 8 |
| 簽章解析回歸測試 | 4 |
| 兩部 YouTube 影片完整下載、影音合併、長度及可播放性 | 2 |
| iPhone 模擬器：無效連結、取消、下載進度及相簿寫入 | 3 |
| iPhone 模擬器：URL、文字、屬性文字及無效分享輸入 | 4 |
| iPhone 模擬器：主畫面操作 | 1 |

真實影片測試包含 `_pJQFrTU4aQ` 與 Blender Foundation 的 `aqz-KE-bpKQ`。測試會下載完整影音軌，合併並核對長度，不以成功讀取檔案開頭代替完整下載。

所有測試組的實際 outcome 都必須是 success，才會執行 Release 打包。為讓每組都執行，測試步驟可能繼續進行；請查看最終「Require every test suite to pass before packaging」及完整日誌，勿只看單一步驟的顏色。

失敗時會保留 integration.log、模擬器編譯／測試紀錄及 xcresult，且不會產生新版 IPA。自動測試不代表已經在使用者的實體 iPhone 驗證。

## 程式拆分

- `Shared/Downloader.swift`：解析、品質選擇、分軌下載、合併、相簿寫入。
- `Shared/DownloadView.swift`：主 App 及分享入口共用介面。
- `Shared/YouTubeLink.swift`：連結驗證。
- `Shared/SharedLinkReader.swift`：iOS 分享輸入的型別化載入。
- `Shared/MediaMuxer.swift`：App 與整合測試共用的影音合併器。
- `Scripts/prepare_vendor.py`：驗證來源 SHA256，準備固定版本的 YouTubeKit 與相容性修正。
- `ShareExtension/`：YouTube 分享連結接收。
- `project.yml`：XcodeGen 專案與 Extension。
- `.github/workflows/build-ios.yml`：macOS 虛擬機測試、編譯及 IPA 打包。

使用 [YouTubeKit](https://github.com/alexeichhorn/YouTubeKit)（MIT），固定 revision 以便重現編譯。YouTubeKit 授權亦包含於 App 的「開放原始碼授權」。此專案與 YouTube／Google 無隸屬關係。

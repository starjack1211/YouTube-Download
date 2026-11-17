# 影片下載 · iPhone
iOS 17+ SwiftUI 介面，下載核心已改為隨 App 內嵌的 Python 3.13、yt-dlp 與官方 EJS。手機無需另外安裝 Python，也不使用遠端解析服務。
版本 2.0.0 / build 4 的程式已完成移植；實機可用性以 TEST_RESULTS.md 和 Actions 測試結果為準。

## 功能
- 貼上 YouTube 影片、Shorts 或直播回放連結；也可從 YouTube 分享到「下載到相簿」。
- 畫質上限 360p、480p、720p、1080p、1440p、2160p。
- AAC 音質上限 64、128、256 kbps 或最高可用；來源沒有符合上限的音軌時採最低可用音軌並告知。
- 顯示下載進度、速度、剩餘時間；支援取消。
- Python 分別下載原始 MP4/AAC；AVFoundation 合併後存入相簿，保留 App 內副本。
- 相簿只要求加入權限。分享入口與主程式各自保存設定。

## 安裝
Actions 的 Build iPhone IPA 必須所有測試都成功，才會產生 YouTubeDownload-IPA。解壓後使用 iLoader 重新簽署安裝，保留 Share Extension。
不應將舊版 IPA 當成 Python 新版；不應將 continue-on-error 步驟的表面成功當成測試通過。

## 開發與測試
在 macOS 安裝 Xcode、XcodeGen：
```sh
brew install xcodegen
python3 Scripts/prepare_python.py
PYTHONPATH=PythonApp:Vendor/python_packages python3 -m unittest discover -s PythonTests -p test_download_core.py -v
swift test
RUN_LIVE_TESTS=1 PYTHONPATH=PythonApp:Vendor/python_packages python3 -m unittest discover -s PythonTests -p test_live.py -v
python3 Scripts/make_icon.py
xcodegen generate
bash Scripts/test_simulator.sh
```
Config/python-lock.json 固定依賴版本與 SHA256。PythonBridge 使用 CPython C API；YouTube 的 JavaScript 挑戰由 App 內 JavaScriptCore 執行官方 yt-dlp-ejs，不啟動外部 Python、Node 或 ffmpeg。桌面測試使用 Node；手機執行使用內建 JavaScriptCore。

## 程式
- PythonApp/download_core.py：解析、格式選擇、下載與進度。
- PythonApp/ios_jsc.py：JavaScriptCore 解題器。
- PythonBridge/：原生 Python/JavaScriptCore 橋接。
- Shared/PythonBackend.swift：背景工作、進度輪詢與取消。
- Shared/Downloader.swift、MediaMuxer.swift：介面狀態、影音合併與相簿。
- ShareExtension/：分享輸入。
- Scripts/prepare_python.py、embed_python.sh：準備依賴與內嵌標準函式庫。
- .github/workflows/build-ios.yml：Mac 測試與打包；以步驟實際 outcome 作為交付門檻。

## 限制
YouTube 可能要求登入、防機器人驗證或限制地區；更換為 Python 不保證繞過這些限制，也不保證每部影片的簽名挑戰都能解開。不支援私人、會員、付費、DRM 內容或正在直播的影片。
分享 Extension 受 iOS 記憶體與執行時間限制，長影片請使用主程式並保持開啟。本版未宣稱支援背景下載。支援的畫質由來源與裝置編碼能力決定。
請僅下載有權下載的內容。授權聲明包含於 App；CPython、yt-dlp、EJS、certifi 依各自授權使用。本專案與 YouTube / Google 無隸屬關係。

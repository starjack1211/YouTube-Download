# Python 版驗證紀錄

版本：2.0.0（build 4）。下載核心為內嵌 CPython 3.13.18、yt-dlp 2026.10.26、yt-dlp-ejs 0.8.0。SwiftUI、AVFoundation 與相簿寫入保留原生實作。

## 已完成的驗證

| 項目 | 結果 | 證據 |
| --- | --- | --- |
| Windows Python 核心及提供者測試 | 18/18 通過 | 包含真實 HTTP 分軌下載、檔案內容、進度、品質選擇、取消與錯誤結果處理 |
| Windows 真實 YouTube 下載 | 2/2 通過，27.614 秒 | 原影片 `_pJQFrTU4aQ` 與參考影片 `aqz-KE-bpKQ`，實際下載影音檔案 |
| macOS Python 測試（修正後） | 18/18 通過 | [Run 44145166430](https://github.com/starjack1211/YouTube-Download/actions/runs/44145166430) |
| iPhone 裝置版主 App 與分享 Extension | Release 編譯成功 | [Run 44143507857](https://github.com/starjack1211/YouTube-Download/actions/runs/44143507857)，原生程式碼與最終版本相同；之後僅修正 Python 提供者的錯誤回傳 |
| iPhone 模擬器載入內嵌 Python、SSL 與官方 EJS | 通過 | Python 3.13.18 / OpenSSL 3.5.9 / JavaScriptCore / certifi，含重複呼叫 |
| 原影片播放器 n 挑戰診斷 | 桌面隔離 JavaScript 環境產生非空結果 | 使用先前保存的原影片播放器程式，官方 EJS 求解 |

## 最終完整重跑

程式碼版本：`8f2dd0784c98ed3e61e4be4bc61fb656e50af459`。
[完整重跑 44144915632](https://github.com/starjack1211/YouTube-Download/actions/runs/44144915632) 已完成，結果為 failure。

共 38 個測試案例：**35 通過，3 失敗**。依原始日誌的測試案例計數，未把 XCTest 同一案例的多個斷言算成多項測試。

| 測試套件 | 通過 / 總數 |
| --- | --- |
| Python 核心與提供者 | 18 / 18 |
| Swift 連結與傳輸統計 | 8 / 8 |
| macOS 真實 YouTube 下載 | 0 / 2 |
| iPhone 模擬器（含 UI） | 9 / 10 |

失敗案例：
1. macOS 原影片下載：`_pJQFrTU4aQ` 只允許台灣地區播放；CI 網路被拒。
2. macOS 參考影片下載：`aqz-KE-bpKQ` 要求防機器人登入驗證。
3. iPhone 模擬器原影片下載、進度與相簿：同樣被地區限制擋住，未下載成功，因此相簿端到端驗收未完成。

Python 重複回傳結果的錯誤已修正，該回歸案例在本次完整重跑及獨立 macOS 重跑均通過。其餘兩項 Python 執行環境測試、四項分享輸入測試、取消、無效輸入及 UI 測試皆通過。

驗收閘門的實際輸出：
```text
Python tests: success
Swift tests: success
Live YouTube tests: failure
iPhone simulator tests: failure
```


## 交付狀態

尚無核准交付的 Python 版 IPA。工作流程會核對所有測試步驟的實際 outcome；完整驗收未通過便不打包。不能把 continue-on-error 顯示的 success 當成測試通過。

GitHub Mac 的 YouTube 地區或防機器人限制不能由更換 Python 自動消除。相簿完整流程仍需成功下載後才能完成驗收。上述本機下載成功不代表 iPhone 相簿端到端驗收已通過。

outputs 中先前的 1.1 IPA 是舊 Swift 下載核心，不是本次 Python 版本。

## 已修正的問題

- 將舊下載核心替換為 yt-dlp 與官方 EJS。
- 透過原生 JavaScriptCore 執行挑戰；手機不需 Node、Python 安裝程式或遠端解析伺服器。
- 分軌下載後由 AVFoundation 合併，不依賴手機上的 ffmpeg。
- 進度由原子 JSON 檔回報，介面保留進度、速度、剩餘時間及取消。
- 固定 Python 與相依套件版本及 SHA256。
- 解題器某一筆結果缺失時，先完成整批驗證再回傳，避免同一請求重複出現。

# 測試結果：尚未達到交付條件

本次測試程式版本：`3e8f561771d3fa67e6093535e4125c0bf41ee6d8`。

[完整 GitHub Actions 執行紀錄](https://github.com/starjack1211/YouTube-Download/actions/runs/44127748182)

結果：**22 項測試已執行；19 項通過，3 項失敗。沒有產生新版 IPA。**

## 已通過

| 範圍 | 通過數 |
| --- | ---: |
| 連結驗證、容量進度、速度、剩餘時間、停滯處理 | 8 |
| 簽章求解器回歸測試 | 4 |
| iOS 分享 URL、文字、屬性文字與無效輸入 | 4 |
| iOS 無效連結及取消下載 | 2 |
| iOS 主畫面與連結輸入操作 | 1 |

其中 URL 分享測試在改用型別化 NSURL 載入後已通過。簽章回歸測試通過，不代表實際 YouTube 影片下載已驗證成功。

## 未通過

| 測試 | 結果與觀察 |
| --- | --- |
| Mac：`_pJQFrTU4aQ` 完整下載與合併 | YouTube 媒體來源回傳「The uploader has not made this video available in your country」，未能取得影音軌。 |
| Mac：`aqz-KE-bpKQ` 完整下載與合併 | YouTube 媒體來源回傳「Sign in to confirm you’re not a bot」，未能取得影音軌。 |
| iOS 模擬器：`_pJQFrTU4aQ` 下載、進度及相簿寫入 | 在影片解析階段中止；套件呈現 Video age restricted。沒有輸出檔案，因此本次未驗證成功下載後的相簿寫入。 |

這些是實際失敗，沒有改成略過或接受錯誤以使測試顯示成功。部分步驟設定 continue-on-error，是為了讓其餘測試仍能執行；最後交付檢查使用實際 outcome，已阻擋 Release 打包。

## 已實作、仍待真實下載驗證的恢復處理

- 保留 YouTube 自動核發的匿名工作階段，讓播放頁面與後續請求延續 Cookie。
- 簽章解析重試時重新取得播放頁面、設定與播放器 JavaScript，避免只重試舊頁面中的播放器資料。
- 單一來源解析失敗時保留其他來源已取得的格式，並保留取消下載的行為。
- 已簽署且沒有 n/s 輸入的媒體網址不再執行不必要的簽章求解。
- 空的求解請求被移除，重複的 n/s 輸入被去重。
- 分享入口改用型別化 URL 載入，並保留文字等備援格式。

尚不能宣稱原始的「Signature solver error for n: no solutions」已在使用者實際影片上完成端到端修復驗證。

## 尚缺的驗證條件

需要能正常播放該影片、且可通過 YouTube 播放驗證的 iPhone 或 Mac 網路環境，重新驗證完整影像／音軌下載、MP4 合併及相簿寫入。

沒有進行使用者實體 iPhone 測試。原工作電腦連線也已中斷，沒有更新原 outputs 資料夾的 IPA；既有 v1.1.0 檔案不代表這次的修正版。

失敗紀錄與 xcresult 保留在本次執行的 build-log artifact，供後續排查。

# Bopomofo Game（Flutter Source Pack）

你要求的：Flutter 版本 + 題型 A/B/C + 離線資料庫（原始轉檔 + 強化版）  
這個資料夾提供「可直接用 Flutter 建置成 Android APK」的**專案原始碼包**（Source Pack）。

> 我目前的執行環境沒有安裝 Flutter，因此**無法在此直接產出 .apk**；但我已把專案與資料庫檔準備好，你在本機（已安裝 Flutter/Android SDK）可用下列指令一鍵建置 APK。

---

## 1) 內容物

- `lib/`：遊戲主程式（題型 A/B/C + TTS）
- `assets/db/moe_enhanced.db`：強化版（含 `word_char.cp_id` 去歧義）
- `assets/db/moe_raw.db`：原始轉檔版（保留教育部原欄位；供你查核/比對）

資料來源：教育部《國語小字典》《國語辭典簡編本》下載版 xlsx 轉檔。

---

## 2) 本機建立 Flutter 專案（建議步驟）

### 方式 A（推薦）：用 flutter create 建乾淨模板，再覆蓋本 Source Pack

```bash
flutter create bopomofo_game
cd bopomofo_game

# 把本資料夾的內容覆蓋進去（lib / assets / pubspec.yaml）
cp -r /path/to/bopomofo_flutter_game_src/lib .
cp -r /path/to/bopomofo_flutter_game_src/assets .
cp /path/to/bopomofo_flutter_game_src/pubspec.yaml .

flutter pub get
flutter run
```

### 產出 APK

```bash
flutter build apk --release
```

輸出通常在：
`build/app/outputs/flutter-apk/app-release.apk`

---

## 3) 題型對應

本專案內的題型命名：
- A：聽音選字（Audio → Char）：TTS 朗讀「詞語」，挖空其中一字，選同音字干擾
- B：看字選音（Char → Bopomofo）：先用**單音字**出題（避免歧義）；之後可擴充多音字語境題
- C：配對（Pairing）：詞語 ↔ 注音配對（使用詞語語境，最穩）
- D：看注音選字（Bopo → Char）：直接顯示注音，選出對應的字
- E：看詞語選注音（Word → Bopo）：直接顯示詞語，選出對應的注音
- 混合題型：每一題隨機出 A/B/C/D/E

---

## 5) 新增玩法（規則/目標/計分）

首頁除了「題型」外，另外新增「玩法（規則/目標）」可選：

- 練習：不扣分，預設目標「答對 10 題」可自訂
- 目標分數：答對加分、答錯扣分，達到目標分數即完成（預設 80 分可自訂）
- 目標題數：答對加分、答錯扣分，達到目標答對題數即完成（預設 20 題可自訂）
- 限時：倒數秒數，時間到即結束（預設 60 秒可自訂）
- 生存：答錯扣 1 命，歸零即結束；同時可設定「答對幾題算完成」（預設 3 命 / 20 題）

答題互動優化：
- **答對後鎖定**：答對之後不可再作答，只能按「下一題」
- **顏色回饋**：答對顯示綠色、答錯顯示紅色（同一個錯誤選項會被停用，避免重複點）

---

## 4) 重要提醒（授權）

教育部資料下載頁使用說明為 CC BY-ND（禁止改作）。  
本包同時提供：
- `moe_raw.db`：屬「格式轉換」概念（原始欄位轉 SQLite）
- `moe_enhanced.db`：為了遊戲用做了結構化/推定欄位（可能被視為改作風險）

若你要把強化版資料隨 App 散布，請你自行評估授權風險。

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

---

## 4) 重要提醒（授權）

教育部資料下載頁使用說明為 CC BY-ND（禁止改作）。  
本包同時提供：
- `moe_raw.db`：屬「格式轉換」概念（原始欄位轉 SQLite）
- `moe_enhanced.db`：為了遊戲用做了結構化/推定欄位（可能被視為改作風險）

若你要把強化版資料隨 App 散布，請你自行評估授權風險。


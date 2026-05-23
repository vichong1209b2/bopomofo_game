#!/usr/bin/env bash
set -euo pipefail

# 目的：
# 1) 產生完整 Flutter 專案骨架（包含 android/ 以便 build apk）
# 2) 把本 Source Pack 的 lib/assets/pubspec.yaml 覆蓋進專案

APP_DIR="bopomofo_game"

if ! command -v flutter >/dev/null 2>&1; then
  echo "找不到 flutter 指令。請先安裝 Flutter SDK，或改用 BUILD_APK.md 的 GitHub Actions 方案。"
  exit 1
fi

if [ -d "${APP_DIR}" ]; then
  echo "已存在 ${APP_DIR}/，跳過 flutter create。"
else
  flutter create "${APP_DIR}"
fi

# 設定 Android 桌面顯示名稱（App label）
python3 - <<'PY'
from pathlib import Path
import re

app_dir = Path("bopomofo_game")
label = "注音遊戲"

manifest = app_dir / "android/app/src/main/AndroidManifest.xml"
if manifest.exists():
  s = manifest.read_text(encoding="utf-8")
  # android:label="xxx" → android:label="注音遊戲"
  s2 = re.sub(r'android:label="[^"]*"', f'android:label="{label}"', s)

  # Android 11+ 的 package visibility 會讓某些 API（例如列舉 TTS 引擎/voices）回傳空清單。
  # 這裡加入 queries，允許查詢提供 TTS_SERVICE 的套件（包含 Google TTS）。
  if "<queries>" not in s2:
    queries = r'''
  <queries>
    <intent>
      <action android:name="android.intent.action.TTS_SERVICE" />
    </intent>
    <package android:name="com.google.android.tts" />
  </queries>
'''.rstrip("\n")
    s2 = re.sub(r'(<manifest[^>]*>)', r'\1\n' + queries, s2, count=1)

  manifest.write_text(s2, encoding="utf-8")

strings = app_dir / "android/app/src/main/res/values/strings.xml"
if strings.exists():
  s = strings.read_text(encoding="utf-8")
  s2 = re.sub(r'(<string\\s+name=\"app_name\">)(.*?)(</string>)', rf'\\1{label}\\3', s)
  strings.write_text(s2, encoding="utf-8")
PY

cp -r ./lib "${APP_DIR}/"
cp -r ./assets "${APP_DIR}/"
cp ./pubspec.yaml "${APP_DIR}/pubspec.yaml"

# 覆蓋 Android 桌面圖示（避免需要額外的 workflow 權限）
ICON_RES_SRC="./assets/icon/android_res"
ICON_RES_DST="${APP_DIR}/android/app/src/main/res"
if [ -d "${ICON_RES_SRC}" ] && [ -d "${ICON_RES_DST}" ]; then
  cp -r "${ICON_RES_SRC}/." "${ICON_RES_DST}/"
  echo "已更新 Android 桌面圖示"
fi

echo "完成：已建立/更新 ${APP_DIR}/"
echo "下一步：cd ${APP_DIR} && flutter pub get && flutter build apk --release"

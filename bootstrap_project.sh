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

cp -r ./lib "${APP_DIR}/"
cp -r ./assets "${APP_DIR}/"
cp ./pubspec.yaml "${APP_DIR}/pubspec.yaml"

echo "完成：已建立/更新 ${APP_DIR}/"
echo "下一步：cd ${APP_DIR} && flutter pub get && flutter build apk --release"


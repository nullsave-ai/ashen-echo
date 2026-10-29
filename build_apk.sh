#!/bin/bash
set -e

REPO="nullsave-ai/ashen-echo"
WORKFLOW="android_build.yml"
FINAL_APK="/storage/emulated/0/Download/AshenEcho.apk"
LOCAL_APK="/storage/emulated/0/Game/ashen_echo/AshenEcho.apk"

echo "=== Ashen Echo - Build & Download APK ==="

echo "Triggering GitHub Actions build..."
gh workflow run "$WORKFLOW" --repo "$REPO"

echo "Waiting for run to start..."
sleep 5

RUN_ID=$(gh run list --repo "$REPO" --limit 1 --json databaseId -q '.[0].databaseId')
echo "Tracking Run ID: $RUN_ID"

gh run watch "$RUN_ID" --repo "$REPO"

echo "Build finished! Fetching latest Release APK..."
gh release download --repo "$REPO" --pattern "*.apk" --dir /storage/emulated/0/Download/ --clobber
cp -f "$FINAL_APK" "$LOCAL_APK"

echo "=== SUCCESS: APK downloaded and ready! ==="
ls -lh "$FINAL_APK"

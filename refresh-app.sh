#!/bin/bash
# CodingQuotaBar 自动刷新签名脚本
# 每5天运行一次，重新 build + install 到手机，绕过7天过期限制

set -euo pipefail

PROJECT_DIR="/Users/kyatai/.openclaw/workspace/coding-quota-bar-ios"
DERIVED_DATA_ROOT="$HOME/Library/Developer/Xcode/DerivedData"
DEVICE_ID="7911C8B2-BA53-5127-80AE-A44F05261CE4"
LOG_FILE="/tmp/codingquotabar-refresh.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$DATE] Starting CodingQuotaBar refresh..." >> "$LOG_FILE"

# 1. Ensure Xcode is running with the project open
osascript -e 'tell application "Xcode" to activate' 2>&1 >> "$LOG_FILE"
sleep 3

# Check if project is open, if not open it
PROJECT_OPEN=$(osascript -e '
tell application "Xcode"
    set ws to name of every workspace document
    if ws contains "CodingQuotaBar.xcodeproj" then
        return "YES"
    else
        return "NO"
    end if
end tell
' 2>&1)

if [ "$PROJECT_OPEN" = "NO" ]; then
    echo "[$DATE] Opening project..." >> "$LOG_FILE"
    open -a Xcode "$PROJECT_DIR/CodingQuotaBar.xcodeproj"
    sleep 10
fi

# 2. Trigger build via AppleScript (uses Xcode GUI's authenticated session)
echo "[$DATE] Starting build..." >> "$LOG_FILE"
RESULT_ID=$(osascript <<'APPLESCRIPT'
tell application "Xcode"
    set activeWorkspaceDocument to workspace document "CodingQuotaBar.xcodeproj"
    set res to build activeWorkspaceDocument
    return id of res
end tell
APPLESCRIPT
2>&1)

echo "[$DATE] Build triggered, result ID: $RESULT_ID" >> "$LOG_FILE"

# 3. Wait for build to complete (max 10 minutes)
echo "[$DATE] Waiting for build..." >> "$LOG_FILE"
for i in $(seq 1 120); do
    sleep 5
    STATUS=$(osascript -e "
tell application \"Xcode\"
    set ws to workspace document \"CodingQuotaBar.xcodeproj\"
    try
        set res to scheme action result id \"$RESULT_ID\" of ws
        return (status of res as text)
    on error
        return \"NOT_FOUND\"
    end try
end tell
" 2>&1)

    if [ "$STATUS" = "succeeded" ]; then
        echo "[$DATE] Build succeeded!" >> "$LOG_FILE"
        break
    elif [ "$STATUS" = "failed" ] || [ "$STATUS" = "cancelled" ]; then
        echo "[$DATE] Build FAILED: $STATUS" >> "$LOG_FILE"
        echo "BUILD_FAILED" >> "$LOG_FILE"
        exit 1
    fi
done

if [ "$STATUS" != "succeeded" ]; then
    echo "[$DATE] Build timed out, last status: $STATUS" >> "$LOG_FILE"
    echo "BUILD_TIMEOUT" >> "$LOG_FILE"
    exit 1
fi

# 4. Find and install the .app
APP_PATH=$(find "$DERIVED_DATA_ROOT/CodingQuotaBar-"*/Build/Products/Debug-iphoneos/ -name "CodingQuotaBar.app" -maxdepth 1 -type d 2>/dev/null | head -1)

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "[$DATE] ERROR: .app not found in DerivedData" >> "$LOG_FILE"
    exit 1
fi

echo "[$DATE] Installing $APP_PATH..." >> "$LOG_FILE"
INSTALL_OUTPUT=$(xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH" 2>&1)
echo "[$DATE] $INSTALL_OUTPUT" >> "$LOG_FILE"

# 5. Verify installation
if echo "$INSTALL_OUTPUT" | grep -q "App installed"; then
    echo "[$DATE] ✅ Refresh complete! App reinstalled successfully." >> "$LOG_FILE"
    echo "SUCCESS"
else
    echo "[$DATE] ❌ Install may have failed" >> "$LOG_FILE"
    echo "INSTALL_MAYBE_FAILED"
fi

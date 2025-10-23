#!/usr/bin/env bash
set -euo pipefail

# Deploy the just-built .app to multiple iOS Simulators and launch it.
#
# Usage (Xcode Run → Post-action recommended):
#   - In Xcode, Edit Scheme… → Run → Post-actions → + New Run Script Action
#   - Set "Provide build settings from" to your app target (e.g., GlobalBridge)
#   - Script: bash "${SRCROOT}/scripts/deploy-to-simulators.sh"
#   - Optionally set env var SIM_DEVICE_NAMES to a comma-separated list of simulator names
#     e.g., SIM_DEVICE_NAMES="iPhone 17,iPhone 17 Pro,iPhone 17 Pro Max"
#
# It will use Xcode-provided env vars to locate the built app and bundle id.

log() { echo "[multi-sim] $*"; }
warn() { echo "[multi-sim][WARN] $*" >&2; }
err()  { echo "[multi-sim][ERROR] $*" >&2; }

[[ -n "${MULTI_SIM_DEBUG:-}" ]] && set -x

# Resolve .app path from Xcode env when available
APP_PATH=""
if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${WRAPPER_NAME:-}" ]]; then
  if [[ -d "${TARGET_BUILD_DIR}/${WRAPPER_NAME}" ]]; then
    APP_PATH="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
  fi
fi

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  warn "Xcode build env not fully available or .app not at expected path. Trying fallback search in DerivedData."

  # Optional hints
  SEARCH_ROOT="${APP_SEARCH_ROOT:-${HOME}/Library/Developer/Xcode/DerivedData}"
  NAME_FILTER="${APP_WRAPPER_NAME:-*.app}"

  # macOS-friendly fallback: find all simulator .app bundles, sort by mtime, pick most recent
  # Optionally filter by APP_WRAPPER_NAME if provided (e.g., GlobalBridge.app)
  mapfile -t CANDIDATES < <(find "$SEARCH_ROOT" -type d -path "*/Build/Products/*-iphonesimulator/${NAME_FILTER}" 2>/dev/null)

  if [[ ${#CANDIDATES[@]} -gt 0 ]]; then
    # Build a list of "mtime path" and pick newest
    NEWEST_LINE=$(for p in "${CANDIDATES[@]}"; do
      [[ -d "$p" ]] || continue
      mt=$(stat -f "%m" "$p" 2>/dev/null || echo 0)
      echo "$mt $p"
    done | sort -nr | head -n1)
    APP_PATH=${NEWEST_LINE#* }
  fi
fi

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  err "Failed to locate built .app. Ensure this runs as a Run Post-action with 'Provide build settings from' set to your target, or set APP_WRAPPER_NAME/APP_SEARCH_ROOT."
  exit 1
fi

log "Using app: ${APP_PATH}"

# Resolve bundle identifier: prefer Xcode env, fallback to Info.plist
BUNDLE_ID=${PRODUCT_BUNDLE_IDENTIFIER:-}
if [[ -z "${BUNDLE_ID}" ]]; then
  INFO_PLIST="${APP_PATH}/Info.plist"
  if [[ -f "${INFO_PLIST}" ]]; then
    if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
      BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}" 2>/dev/null || true)
    fi
    if [[ -z "${BUNDLE_ID}" ]] && command -v plutil >/dev/null 2>&1; then
      BUNDLE_ID=$(plutil -extract CFBundleIdentifier raw -o - "${INFO_PLIST}" 2>/dev/null || true)
    fi
  fi
fi

if [[ -z "${BUNDLE_ID}" ]]; then
  err "Could not resolve bundle identifier. Set PRODUCT_BUNDLE_IDENTIFIER in env or ensure Info.plist is readable."
  exit 1
fi

log "Bundle ID: ${BUNDLE_ID}"

# Target simulators: names or UDIDs, comma-separated. Default to iPhone 17 family as requested.
SIM_DEVICE_NAMES=${SIM_DEVICE_NAMES:-"iPhone 17,iPhone 17 Pro,iPhone 17 Pro Max"}

IFS=',' read -r -a DEVICES <<< "${SIM_DEVICE_NAMES}"

# Get first UDID match for a device name
udid_for_name() {
  local name="$1"
  # Prefer available devices; fall back to any device if needed.
  local udid
  udid=$(xcrun simctl list devices available 2>/dev/null | \
    awk -v n="$name" '$0 ~ n { if (match($0, /\(([0-9A-F-]+)\)/, m)) { print m[1]; exit } }')
  if [[ -z "$udid" ]]; then
    udid=$(xcrun simctl list devices 2>/dev/null | \
      awk -v n="$name" '$0 ~ n { if (match($0, /\(([0-9A-F-]+)\)/, m)) { print m[1]; exit } }')
  fi
  echo "$udid"
}

is_booted() {
  local udid="$1"
  xcrun simctl list devices 2>/dev/null | grep -q "${udid} (Booted)"
}

install_and_launch() {
  local udid="$1"
  local app="$2"
  local bundle="$3"

  if ! is_booted "$udid"; then
    log "Booting simulator $udid…"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    # Wait for boot to complete
    xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  fi

  # Give CoreSimulator a moment if just booted
  sleep 1

  # Best-effort uninstall to avoid stale installs
  xcrun simctl uninstall "$udid" "$bundle" >/dev/null 2>&1 || true
  log "Installing app to $udid…"
  xcrun simctl install "$udid" "$app"

  log "Launching $bundle on $udid…"
  # Launch without attaching a debugger; background ampersand to parallelize
  xcrun simctl launch "$udid" "$bundle" >/dev/null 2>&1 &
}

log "Target simulators: ${SIM_DEVICE_NAMES}"

declare -a TARGET_UDIDS=()
for name in "${DEVICES[@]}"; do
  name_trimmed="${name//\n/}"
  name_trimmed="${name_trimmed## }"; name_trimmed="${name_trimmed%% }"
  if [[ -z "$name_trimmed" ]]; then continue; fi
  udid=$(udid_for_name "$name_trimmed")
  if [[ -z "$udid" ]]; then
    warn "Could not find a simulator matching: '$name_trimmed'"
    continue
  fi
  TARGET_UDIDS+=("$udid")
done

if [[ ${#TARGET_UDIDS[@]} -eq 0 ]]; then
  err "No target simulators resolved. Check SIM_DEVICE_NAMES or installed simulators."
  exit 1
fi

for udid in "${TARGET_UDIDS[@]}"; do
  # Avoid double-launch on the same simulator Xcode already targeted
  if [[ -n "${TARGET_DEVICE_IDENTIFIER:-}" && "${udid}" == "${TARGET_DEVICE_IDENTIFIER}" ]]; then
    log "Skipping selected run destination (already handled by Xcode): ${udid}"
    continue
  fi
  install_and_launch "$udid" "$APP_PATH" "$BUNDLE_ID"
done

wait || true
log "All launch requests issued."

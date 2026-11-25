# Vicu Project Rules

## Mandatory Physical Device Installation

Every change that affects the iOS app (Swift code, SwiftUI views, resources, localization, assets, widgets, or Xcode project configuration) **must** be built and installed onto a connected physical iOS device before completing the task.

### Required Workflow

1. **Discover the connected physical device**:
   ```bash
   xcrun devicectl list devices
   ```
   Locate the physical device whose state is `connected` (e.g., `Starriv’s iPhone`, iPhone 17 Pro Max).

2. **Build for the physical device**:
   ```bash
   xcodebuild build \
     -project vicu.xcodeproj \
     -scheme vicu \
     -destination 'platform=iOS,id=<DEVICE_UDID>' \
     -allowProvisioningUpdates
   ```

3. **Resolve the built `.app` bundle and install it**:
   ```bash
   APP_PATH=$(xcodebuild -project vicu.xcodeproj -scheme vicu -destination 'platform=iOS,id=<DEVICE_UDID>' -showBuildSettings 2>/dev/null | awk '/ TARGET_BUILD_DIR = / {dir=$3} / FULL_PRODUCT_NAME = / {name=$3} END {print dir "/" name}')
   xcrun devicectl device install app --device <DEVICE_UDID> "$APP_PATH"
   ```

### Notes

- Do **not** treat simulator-only builds or tests as sufficient when iOS app files have changed — always complete the physical device installation step.
- If no physical iOS device is currently connected, unlocked, or reachable (or if code signing requires user intervention), explicitly report the block to the user rather than silently skipping installation.
- Changes strictly limited to non-iOS files (such as `docs/`, `website/`, or rule/config markdown files) do not require rebuilding and reinstalling the iOS app unless the user requests it.

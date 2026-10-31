#!/usr/bin/env bash
# Generates the Android project around lib/ and applies the required settings.
# Run once from the project root:  bash scripts/setup_android.sh
set -euo pipefail
command -v flutter >/dev/null || { echo "Flutter is not installed. See https://docs.flutter.dev/get-started/install"; exit 1; }

flutter create --platforms=android --org com.smartschool --project-name smart_school .
python3 scripts/patch_android.py
flutter pub get
echo "Done. Next: flutter test && see README step 6 to build the APK."

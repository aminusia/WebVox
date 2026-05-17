#!/usr/bin/env sh
set -eu

PUBSPEC="pubspec.yaml"
DIST_DIR="dist"
FLUTTER_APK="build/app/outputs/flutter-apk/app-release.apk"

# Parse command-line options
SKIP_VERSION_BUMP=false
PUBLISH=false
while [ $# -gt 0 ]; do
  case "$1" in
    --no-bump|--skip-bump|stall)
      SKIP_VERSION_BUMP=true
      shift
      ;;
    --publish|publish)
      PUBLISH=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--no-bump|--skip-bump|stall] [--publish|publish]" >&2
      exit 1
      ;;
  esac
done

if [ ! -f "$PUBSPEC" ]; then
  echo "Error: $PUBSPEC not found." >&2
  exit 1
fi

package_line=$(grep -E '^name:' "$PUBSPEC" | head -n 1)
if [ -z "$package_line" ]; then
  echo "Error: name line not found in $PUBSPEC." >&2
  exit 1
fi
package_name=$(printf '%s' "$package_line" | sed 's/^name:[[:space:]]*//')

version_line=$(grep -E '^version:' "$PUBSPEC" | head -n 1)
if [ -z "$version_line" ]; then
  echo "Error: version line not found in $PUBSPEC." >&2
  exit 1
fi

version_string=$(printf '%s' "$version_line" | sed 's/^version:[[:space:]]*//')
version_core=${version_string%%+*}
build_number=${version_string##*+}

if [ "$version_core" = "$build_number" ]; then
  echo "Error: version in $PUBSPEC must include a build number like 1.0.0+1." >&2
  exit 1
fi

case "$build_number" in
  ''|*[!0-9]*)
    echo "Error: invalid build number '$build_number' in version string." >&2
    exit 1
    ;;
esac

if ! echo "$version_core" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "Error: version core '$version_core' must be in MAJOR.MINOR.PATCH format." >&2
  exit 1
fi

if [ "$SKIP_VERSION_BUMP" = false ]; then
  major_minor=${version_core%.*}
  patch=${version_core##*.}
  new_patch=$((patch + 1))
  new_version_core="${major_minor}.${new_patch}"
  new_build_number=$((build_number + 1))
  new_version="${new_version_core}+${new_build_number}"

  printf 'Bumping version %s -> %s in %s\n' "$version_string" "$new_version" "$PUBSPEC"
  perl -pi -e 's/^version: .*/version: '$new_version'/' "$PUBSPEC"
else
  new_version="$version_string"
  printf 'Skipping version bump. Using version %s\n' "$new_version"
fi

printf 'Building release Bundle...\n'
flutter build appbundle --release

printf 'Building release APK...\n'
flutter build apk --release

if [ ! -f "$FLUTTER_APK" ]; then
  echo "Error: APK not found at $FLUTTER_APK." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
dest="$DIST_DIR/${package_name}-${new_version}.apk"
cp "$FLUTTER_APK" "$dest"
cp "$FLUTTER_APK" "$DIST_DIR/${package_name}-latest.apk"

printf 'Release APK copied to %s\n' "$dest"
printf 'Also copied latest APK to %s\n' "$DIST_DIR/${package_name}-latest.apk"

if [ "$PUBLISH" = true ]; then
  fastlane android deploy_internal publish
fi
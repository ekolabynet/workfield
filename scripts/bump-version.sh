#!/usr/bin/env bash
# Uzycie: ./scripts/bump-version.sh 0.6.1
set -e
V="$1"
[[ "$V" =~ ^0\.([0-9]+)\.([0-9]+)$ ]] || { echo "Format: 0.MINOR.PATCH"; exit 1; }
CODE=$((${BASH_REMATCH[1]}*100 + ${BASH_REMATCH[2]}))
sed -i "s|APK_VERSION_CODE:-[0-9]*}|APK_VERSION_CODE:-$CODE}|" scripts/build.sh
sed -i "s|APP_VERSION_STR:-[^}]*}|APP_VERSION_STR:-$V}|" scripts/build.sh
sed -i "s|APK_VERSION_CODE:-[0-9]*}|APK_VERSION_CODE:-$CODE}|" scripts/build-vcpkg.sh
sed -i "s|APP_VERSION:-v[^}]*}|APP_VERSION:-v$V}|" scripts/build-vcpkg.sh
sed -i "s|APP_VERSION_STR:-[^}]*}|APP_VERSION_STR:-$V}|" scripts/build-vcpkg.sh
git add scripts/build.sh scripts/build-vcpkg.sh
git commit -m "Version bump: $V (versionCode $CODE)"
git tag "v$V"
echo "WorkFieldGIS $V / code $CODE - zbuduj: triplet=arm64-android ./scripts/build.sh"

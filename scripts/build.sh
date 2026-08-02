#!/usr/bin/env bash

set -e

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null && pwd)"/..

export APP_VERSION_STR=${APP_VERSION_STR:-0.8.11}
# APP_VERSION (CPack, link do wydania w oknie "O programie") z tego samego zrodla
export APP_VERSION=${APP_VERSION:-v$APP_VERSION_STR}
# versionCode = major*10000 + minor*100 + patch: rosnie takze przy 0.10.x i 1.0.0
export APK_VERSION_CODE=${APK_VERSION_CODE:-$(echo "$APP_VERSION_STR" | awk -F. '{print $1*10000 + $2*100 + $3}')}

# Sekrety podpisu NIE mieszkaja w repo. Zrodlo: scripts/signing.env
# (gitignore) albo zmienne srodowiskowe.
if [ -f "$SRC_DIR/scripts/signing.env" ]; then
  source "$SRC_DIR/scripts/signing.env"
fi
: "${STOREPASS:?Brak STOREPASS - utworz scripts/signing.env (patrz signing.env.example)}"
: "${KEYPASS:?Brak KEYPASS - utworz scripts/signing.env}"
export STOREPASS KEYPASS
export KEYNAME=${KEYNAME:-workfield}

triplet=${triplet:-arm64-android}

if [[ ${triplet} == arm-android ]]; then
	install_qt_arch="android_armv7"
elif [[ ${triplet} == arm-neon-android ]]; then
	install_qt_arch="android_armv7"
elif [[ ${triplet} == arm64-android ]]; then
	install_qt_arch="android_arm64_v8a"
elif [[ ${triplet} == x86-android ]]; then
	install_qt_arch="android_x86"
elif [[ ${triplet} == x64-android ]]; then
	install_qt_arch="android_x86_64"
else
	install_qt_arch="android_arm64_v8a"
fi

DOCKER_BUILDKIT=1 docker build ${SRC_DIR}/.docker/android_dev -t qfield_and_dev

docker run -it --rm qfield_and_dev env
docker run -it --rm \
	-v "$SRC_DIR":/usr/src/qfield:Z \
	$(if [ -n "$CACHE_DIR" ]; then echo "-v $CACHE_DIR:/io/.cache:Z"; fi) \
	-e triplet=${triplet} \
	-e install_qt_version=${install_qt_version} \
	-e install_qt_arch=${install_qt_arch} \
	-e STOREPASS \
	-e KEYNAME \
	-e KEYPASS \
	-e APP_PACKAGE_NAME \
	-e APP_NAME \
	-e APP_ICON \
	-e APP_VERSION \
	-e APP_VERSION_STR \
	-e APK_VERSION_CODE \
	-e NUGET_TOKEN \
	-e NUGET_USERNAME \
	-e USER_GID=$(stat -c "%g" .) \
	-e USER_UID=$(stat -c "%u" .) \
	-e VCPKG_BINARY_SOURCES=clear\;files,/io/.cache,readwrite \
	qfield_and_dev \
	/usr/src/qfield/scripts/build-vcpkg.sh

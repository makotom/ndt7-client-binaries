#!/bin/bash

set -euo pipefail

GOOS_LIST=("linux" "windows" "darwin" "android")
GOARCH_LIST=("amd64" "arm64")
SRC_REPO=${SRC_REPO:-"https://github.com/m-lab/ndt7-client-go.git"}
TARGET_REV=${TARGET_REV:-"master"}

if [[ "${GOOS_LIST_OVERRIDE:-}" ]]; then
    eval GOOS_LIST="${GOOS_LIST_OVERRIDE}"
fi
if [[ "${GOARCH_LIST_OVERRIDE:-}" ]]; then
    eval GOARCH_LIST="${GOARCH_LIST_OVERRIDE}"
fi

fetch_source() {
    rm -fr src

    mkdir src
    pushd src

    git init
    git remote add origin "${SRC_REPO}"
    git fetch --depth 1 origin "${TARGET_REV}"
    git checkout "${TARGET_REV}"

    TARGET_REV="$(git rev-parse HEAD)"

    if [[ -z "${BUILD_NAME:-}" ]]; then
        BUILD_NAME="git-${TARGET_REV:0:7}"
    fi

    popd
}

build_gc() {
    goos=$1
    goarch=$2

    OUTPUT="$(pwd)/dist/${goos}/${goarch}/ndt7-client"
    if [[ "${goos}" == "windows" ]]; then
        OUTPUT="$(pwd)/dist/${goos}/${goarch}/ndt7-client.exe"
    fi

    pushd src/cmd/ndt7-client
    GOOS="${goos}" GOARCH="${goarch}" CGO_ENABLED=0 go build -o "${OUTPUT}" .
    popd
}

build_android() {
    goos=$1
    goarch=$2

    # https://developer.android.com/ndk/downloads
    ndk_label="android-ndk-r23b"
    ndk_archive="${ndk_label}-linux.zip"
    ndk_checksum="f47ec4c4badd11e9f593a8450180884a927c330d"
    ndk_android_version="android31"

    if [[ ! -d "${ndk_label}" ]]; then
        curl -fJOL "https://dl.google.com/android/repository/${ndk_archive}"
        echo "${ndk_checksum} ${ndk_archive}" | sha1sum -c
        unzip "${ndk_archive}"
    fi

    if [[ "${goarch}" == "arm64" ]]; then
        arch_clang="aarch64"
    elif [[ "${goarch}" == "amd64" ]]; then
        arch_clang="x86_64"
    fi

    CC="$(pwd)/${ndk_label}/toolchains/llvm/prebuilt/linux-x86_64/bin/${arch_clang}-linux-${ndk_android_version}-clang"
    CXX="$(pwd)/${ndk_label}/toolchains/llvm/prebuilt/linux-x86_64/bin/${arch_clang}-linux-${ndk_android_version}-clang++"
    OUTPUT="$(pwd)/dist/${goos}/${goarch}/ndt7-client"

    pushd src/cmd/ndt7-client
    CC="${CC}" CXX="${CXX}" GOOS="${goos}" GOARCH="${goarch}" CGO_ENABLED=1 go build -o "${OUTPUT}" .
    popd
}

package() {
    goos=$1
    goarch=$2

    cp --no-preserve=all src/LICENSE src/AUTHORS -t "dist/${goos}/${goarch}"

    pushd "dist/${goos}/${goarch}"
    if [[ "${goos}" == "linux" ]] || [[ "${goos}" == "android" ]]; then
        tar -czf "../../ndt7-client-${BUILD_NAME}-${goos}-${goarch}.tar.gz" .
    else
        zip -r "../../ndt7-client-${BUILD_NAME}-${goos}-${goarch}.zip" .
    fi
    popd
}

fetch_source

for goos in "${GOOS_LIST[@]}"; do
    for goarch in "${GOARCH_LIST[@]}"; do
        echo "${goos}/${goarch}"

        mkdir -p "dist/${goos}/${goarch}"

        if [[ "${goos}" == "android" ]]; then
            build_android "${goos}" "${goarch}"
        else
            build_gc "${goos}" "${goarch}"
        fi

        package "${goos}" "${goarch}"
    done
done

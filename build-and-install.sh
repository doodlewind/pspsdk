#!/bin/bash

## Fail script if an error happens
set -e

## Enter the pspsdk directory.
cd "$(dirname "$0")" || { echo "ERROR: Could not enter the pspsdk directory."; exit 1; }

## Make sure PSPDEV is set
if [ -z "${PSPDEV}" ]; then
    echo "The PSPDEV environment variable has not been set"
    exit 1
fi

PROC_NR=$(getconf _NPROCESSORS_ONLN)

find_llvm_tool()
{
    local tool="$1"
    local override="$2"

    if test -n "$override"; then
        printf '%s\n' "$override"
        return 0
    fi

    if command -v brew >/dev/null 2>&1; then
        local brew_llvm
        brew_llvm="$(brew --prefix llvm 2>/dev/null || true)"
        if test -n "$brew_llvm" && test -x "$brew_llvm/bin/$tool"; then
            printf '%s\n' "$brew_llvm/bin/$tool"
            return 0
        fi
    fi

    if command -v "$tool" >/dev/null 2>&1; then
        command -v "$tool"
        return 0
    fi

    echo "ERROR: Could not find $tool. Install LLVM or set PSPSDK_LLVM_BINDIR." >&2
    return 1
}

rebuild_clang_glue()
{
    if [[ "${PSPSDK_CLANG_GLUE:-1}" != "1" ]]; then
        return 0
    fi

    local llvm_bindir="${PSPSDK_LLVM_BINDIR:-}"
    local clang
    local llvm_ar
    local llvm_ranlib
    local llvm_strip
    clang="$(find_llvm_tool clang "${PSPSDK_CLANG_GLUE_CC:-${llvm_bindir:+$llvm_bindir/clang}}")"
    llvm_ar="$(find_llvm_tool llvm-ar "${PSPSDK_LLVM_AR:-${llvm_bindir:+$llvm_bindir/llvm-ar}}")"
    llvm_ranlib="$(find_llvm_tool llvm-ranlib "${PSPSDK_LLVM_RANLIB:-${llvm_bindir:+$llvm_bindir/llvm-ranlib}}")"
    llvm_strip="$(find_llvm_tool llvm-strip "${PSPSDK_LLVM_STRIP:-${llvm_bindir:+$llvm_bindir/llvm-strip}}")"

    local clang_target="${PSPSDK_CLANG_GLUE_TARGET:-mipsel-sony-psp}"
    local clang_target_flags="${PSPSDK_CLANG_GLUE_TARGET_FLAGS:--mcpu=mips2 -msingle-float -mlittle-endian -mno-abicalls -fno-pic -G0 -mno-check-zero-division -fno-stack-protector}"
    local psp_clang="$clang -target $clang_target $clang_target_flags --sysroot=$PSPDEV/psp -isystem $PSPDEV/psp/include -isystem $PSPDEV/psp/sdk/include"
    local glue_cflags="${PSPSDK_CLANG_GLUE_CFLAGS:--O2 -g0 -mabi=32 -mno-abicalls -fno-pic -G0 -mno-gpopt -Wall -Wno-format -Wno-implicit-function-declaration -Wno-deprecated-non-prototype -Wno-unknown-pragmas -Wno-unused-but-set-variable -Wno-unused-variable -Wno-unused-function -D_PSP_FW_VERSION=600}"

    for glue_dir in src/libcglue src/libpthreadglue; do
        make -C "$glue_dir" clean
        make -C "$glue_dir" -j "$PROC_NR" \
            CC="$psp_clang" \
            CCAS="$psp_clang -c" \
            AR="$llvm_ar" \
            RANLIB="$llvm_ranlib" \
            CFLAGS="$glue_cflags" \
            CCASFLAGS="$glue_cflags" \
            install
    done

    "$llvm_strip" --strip-debug \
        "$PSPDEV/psp/sdk/lib/libcglue.a" \
        "$PSPDEV/psp/sdk/lib/libpthreadglue.a"
}

## Build pspsdk
./bootstrap
./configure
make clean
make -j "$PROC_NR"

## Install pspsdk
make install -j "$PROC_NR"
rebuild_clang_glue

## gcc needs to include libcglue libpthreadglue libpspprof libpsputility libpsprtc libpspnet_inet libpspnet_resolver libpspsdk libpspmodinfo libpspuser libpspkernel
## from pspsdk to be able to build executables, because they are part of the standard libraries
cd "$PSPDEV/psp/lib"
ln -sf "../sdk/lib/libcglue.a" "libcglue.a" || { exit 1; }
ln -sf "../sdk/lib/libpthreadglue.a" "libpthreadglue.a" || { exit 1; }
ln -sf "../sdk/lib/libpspprof.a" "libpspprof.a" || { exit 1; }
ln -sf "../sdk/lib/libpsputility.a" "libpsputility.a" || { exit 1; }
ln -sf "../sdk/lib/libpsprtc.a" "libpsprtc.a" || { exit 1; }
ln -sf "../sdk/lib/libpspnet_inet.a" "libpspnet_inet.a" || { exit 1; }
ln -sf "../sdk/lib/libpspnet_resolver.a" "libpspnet_resolver.a" || { exit 1; }
ln -sf "../sdk/lib/libpspsdk.a" "libpspsdk.a" || { exit 1; }
ln -sf "../sdk/lib/libpspmodinfo.a" "libpspmodinfo.a" || { exit 1; }
ln -sf "../sdk/lib/libpspuser.a" "libpspuser.a" || { exit 1; }
ln -sf "../sdk/lib/libpspkernel.a" "libpspkernel.a" || { exit 1; }
cd -

# Copy licenses
mkdir -p $PSPDEV/psp/share/licenses/pspsdk
cp LICENSE $PSPDEV/psp/share/licenses/pspsdk/

mkdir -p $PSPDEV/share/licenses/PrxEncrypter
cp tools/PrxEncrypter/LICENSE $PSPDEV/share/licenses/PrxEncrypter

## Store build information
if [ -d .git ]; then
  BUILD_FILE="${PSPDEV}/build.txt"
  if [[ -f "${BUILD_FILE}" ]]; then
    sed -i.bak '/^pspsdk /d' "${BUILD_FILE}"
    rm -f "${BUILD_FILE}.bak"
  fi
  git log -1 --format="pspsdk %H %cs %s" >> "${BUILD_FILE}"
fi

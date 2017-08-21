# Configuration
# Pod maintainer step 1 of 2. Modify the OPENSSL_VERSION.
OPENSSL_VERSION="1.0.2m"

# Pod maintainer step 2 of 2. Update the checksum file
#
#     shasum -a256 "openssl-${OPENSSL_VERSION}.tar.gz" > checksum
#
# Verify output with the checksum published on https://www.openssl.org/source/

Pod::Spec.new do |s|
  s.name            = "OpenSSL"
  s.version         = "1.0.213"
  s.summary         = "OpenSSL is an SSL/TLS and Crypto toolkit. Deprecated in Mac OS and gone in iOS, this spec gives your project non-deprecated OpenSSL support."
  s.author          = "OpenSSL Project <openssl-dev@openssl.org>"
  s.source          = { http: "https://www.openssl.org/source/openssl-#{OPENSSL_VERSION}.tar.gz", sha256: "8c6ff15ec6b319b50788f42c7abc2890c08ba5a1cdcd3810eb9092deada37b0f" }
  s.homepage        = "https://github.com/WhisperSystems/OpenSSL-Pod"
  s.source_files    = "opensslIncludes/openssl/*.h"
  s.header_dir      = "openssl"
  s.license         = { :type => 'OpenSSL (OpenSSL/SSLeay)', :file => 'LICENSE' }

  s.ios.deployment_target   = "8.0"
  s.ios.public_header_files = "opensslIncludes/openssl/*.h"
  s.ios.vendored_libraries  = "lib/libcrypto.a", "lib/libssl.a"

  s.libraries             = 'crypto', 'ssl'
  s.requires_arc          = false
  s.prepare_command = <<-CMD
    OPENSSL_VERSION="#{OPENSSL_VERSION}"

    CHECKSUM_FILE="checksum"

    SRC_TARBALL="openssl-${OPENSSL_VERSION}.tar.gz"
    SRC_URL="https://www.openssl.org/source/${SRC_TARBALL}"

    if [ -f file.tgz ]
    then
      echo "Using existing file.tgz"
      mv file.tgz $SRC_TARBALL
    else
      echo "Downloading from ${SRC_URL}"
      curl -O "${SRC_URL}"
      if [ ! -f $SRC_TARBALL ]
      then
        echo "Failed to download ${SRC_URL}"
        exit 1
      fi
    fi

    # Ensure checksum matches incase we're installing from development pod
    # (Cocoapods checks for us if we're downloading from source)
    if [ ! -f $CHECKSUM_FILE ]
    then
      echo "Missing checksum file"
      exit 1
    fi

    shasum -c $CHECKSUM_FILE
    if [ $? -eq 0 ]
    then
      echo "Checksum OK."
    else
      echo "Checksum failed."
      exit 1
    fi

    SDKVERSION=`xcrun --sdk iphoneos --show-sdk-version 2> /dev/null`
    MIN_SDK_VERSION_FLAG="-miphoneos-version-min=8.0"

    BASEPATH="${PWD}"
    BUILD_ROOT="/tmp/openssl-pod"

    # Order of ARCHS is somewhat significant since our pod exposes the headers from the last built arch
    ARCHS="i386 x86_64 armv7 armv7s arm64"
    DEVELOPER=`xcode-select -print-path`
    OUTPUT_DIR="${BUILD_ROOT}/output"

    mkdir -p "${OUTPUT_DIR}"

    cp "${SRC_TARBALL}" "${BUILD_ROOT}/${SRC_TARBALL}"
    cd "${BUILD_ROOT}"
    tar -xzf "${SRC_TARBALL}"
    SRC_DIR="openssl-${OPENSSL_VERSION}"
    cd $SRC_DIR

    echo "Building OpenSSL. This will take a while..."
    for ARCH in ${ARCHS}
    do
      CONFIGURE_FOR="iphoneos-cross"

      if [ "${ARCH}" == "i386" ] || [ "${ARCH}" == "x86_64" ] ;
      then
        PLATFORM="iPhoneSimulator"
        if [ "${ARCH}" == "x86_64" ] ;
        then
          CONFIGURE_FOR="darwin64-x86_64-cc"
        fi
      else
        sed -ie "s!static volatile sig_atomic_t intr_signal;!static volatile intr_signal;!" "crypto/ui/ui_openssl.c"
        PLATFORM="iPhoneOS"
      fi

      export CROSS_TOP="${DEVELOPER}/Platforms/${PLATFORM}.platform/Developer"
      export CROSS_SDK="${PLATFORM}${SDKVERSION}.sdk"

      echo "Building openssl-${OPENSSL_VERSION} for ${PLATFORM} ${SDKVERSION} ${ARCH}"
      echo "Please stand by..."

      export CC="${DEVELOPER}/usr/bin/gcc -arch ${ARCH} ${MIN_SDK_VERSION_FLAG}"

      ARCH_OUTPUT_DIR="${OUTPUT_DIR}/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
      mkdir -p "${ARCH_OUTPUT_DIR}"
      SSL_BUILD_LOG="${ARCH_OUTPUT_DIR}/build-openssl-${OPENSSL_VERSION}.log"

      echo "Starting build for ${ARCH} / ${OPENSSL_VERSION}" > $SSL_BUILD_LOG

      ./Configure ${CONFIGURE_FOR} --prefix="${ARCH_OUTPUT_DIR}" --openssldir="${ARCH_OUTPUT_DIR}" >> "${SSL_BUILD_LOG}" 2>&1
      sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} !" "Makefile"

      make -j8 build_libs >> "${SSL_BUILD_LOG}" 2>&1
      make install >> "${SSL_BUILD_LOG}" 2>&1
      make clean >> "${SSL_BUILD_LOG}" 2>&1

      if [ ! -f "${ARCH_OUTPUT_DIR}/lib/libssl.a" ]
      then
        echo "Failed to build ${ARCH_OUTPUT_DIR}/lib/libssl.a"
        echo "See ${SSL_BUILD_LOG} for details"
        exit 1
      fi
      LIBSSL_ACCUM="${LIBSSL_ACCUM} ${ARCH_OUTPUT_DIR}/lib/libssl.a"

      if [ ! -f "${ARCH_OUTPUT_DIR}/lib/libcrypto.a" ]
      then
        echo "Failed to build ${ARCH_OUTPUT_DIR}/lib/libssl.a"
        echo "See ${SSL_BUILD_LOG} for details"
        exit 1
      fi
      LIBCRYPTO_ACCUM="${LIBCRYPTO_ACCUM} ${ARCH_OUTPUT_DIR}/lib/libcrypto.a"
    done

    echo "Copying headers from last built ARCH..."
    rm -rf "${BASEPATH}/opensslIncludes/"
    mkdir -p "${BASEPATH}/opensslIncludes/"
    if [ ! -d "${ARCH_OUTPUT_DIR}/include/openssl" ]
    then
      echo "Failed to find headers ${ARCH_OUTPUT_DIR}/include/openssl"
      echo "See ${SSL_BUILD_LOG} for details"
      exit 1
    fi
    cp -RL "${ARCH_OUTPUT_DIR}/include/openssl" "${BASEPATH}/opensslIncludes/"

    echo "Creating fat library..."
    rm -rf "${BASEPATH}/lib/"
    mkdir -p "${BASEPATH}/lib/"
    lipo -create ${LIBSSL_ACCUM}    -output "${BASEPATH}/lib/libssl.a"
    lipo -create ${LIBCRYPTO_ACCUM} -output "${BASEPATH}/lib/libcrypto.a"

    cd "${BASEPATH}"
    echo "Building done."

    echo "Cleaning up..."
    rm -rf "${BUILD_ROOT}"
    echo "Done."
  CMD

end

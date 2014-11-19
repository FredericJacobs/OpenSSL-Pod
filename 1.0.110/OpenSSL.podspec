Pod::Spec.new do |s|
  s.name            = "OpenSSL"
  s.version         = "1.0.110"
  s.summary         = "OpenSSL is an SSL/TLS and Crypto toolkit. Deprecated in Mac OS and gone in iOS, this spec gives your project non-deprecated OpenSSL support."
  s.author          = "OpenSSL Project <openssl-dev@openssl.org>"

  s.homepage        = "https://github.com/FredericJacobs/OpenSSL-Pod"
  s.license         = 'BSD-style Open Source'
  s.source          = { :http => "https://www.openssl.org/source/openssl-1.0.1j.tar.gz", :sha1 => "cff86857507624f0ad42d922bb6f77c4f1c2b819"}
  s.source_files    = "opensslIncludes/openssl/*.h"
  s.header_dir      = "openssl"
  s.license	        = { :type => 'OpenSSL (OpenSSL/SSLeay)', :file => 'LICENSE' }

  s.prepare_command = <<-CMD
    VERSION="1.0.1j"
    SDKVERSION=`xcrun --sdk iphoneos --show-sdk-version 2> /dev/null`

    BASEPATH="${PWD}"
    CURRENTPATH="/tmp/openssl"
    ARCHS="i386 x86_64 armv7 armv7s arm64"
    DEVELOPER=`xcode-select -print-path`

    mkdir -p "${CURRENTPATH}"
    mkdir -p "${CURRENTPATH}/bin"

    cp "file.tgz" "${CURRENTPATH}/file.tgz"
    cd "${CURRENTPATH}"
    tar -xzf file.tgz
    cd "openssl-${VERSION}"

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

      echo "Building openssl-${VERSION} for ${PLATFORM} ${SDKVERSION} ${ARCH}"
      echo "Please stand by..."

      export CC="${DEVELOPER}/usr/bin/gcc -arch ${ARCH} -miphoneos-version-min=${SDKVERSION}"
      mkdir -p "${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk"
      LOG="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/build-openssl-${VERSION}.log"

      LIPO_LIBSSL="${LIPO_LIBSSL} ${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/lib/libssl.a"
      LIPO_LIBCRYPTO="${LIPO_LIBCRYPTO} ${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk/lib/libcrypto.a"

      ./Configure ${CONFIGURE_FOR} --openssldir="${CURRENTPATH}/bin/${PLATFORM}${SDKVERSION}-${ARCH}.sdk" > "${LOG}" 2>&1
      sed -ie "s!^CFLAG=!CFLAG=-isysroot ${CROSS_TOP}/SDKs/${CROSS_SDK} !" "Makefile"

      make >> "${LOG}" 2>&1
      make all install_sw >> "${LOG}" 2>&1
      make clean >> "${LOG}" 2>&1
    done


    echo "Build library..."
    rm -rf "${BASEPATH}/lib/"
    mkdir -p "${BASEPATH}/lib/"
    lipo -create ${LIPO_LIBSSL}    -output "${BASEPATH}/lib/libssl.a"
    lipo -create ${LIPO_LIBCRYPTO} -output "${BASEPATH}/lib/libcrypto.a"

    echo "Copying headers..."
    rm -rf "${BASEPATH}/opensslIncludes/"
    mkdir -p "${BASEPATH}/opensslIncludes/"
    cp -RL "${CURRENTPATH}/openssl-${VERSION}/include/openssl" "${BASEPATH}/opensslIncludes/"

    cd "${BASEPATH}"
    echo "Building done."

    echo "Cleaning up..."
    rm -rf "${CURRENTPATH}"
    echo "Done."
  CMD

  s.ios.platform            = :ios
  s.ios.public_header_files = "opensslIncludes/openssl/*.h"
  s.ios.vendored_libraries  = "lib/libcrypto.a", "lib/libssl.a"

  s.libraries             = 'crypto', 'ssl'
  s.requires_arc          = false

end

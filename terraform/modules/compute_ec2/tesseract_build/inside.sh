#!/usr/bin/env bash
# Runs inside amazonlinux:2023 arm64 (called by build.sh). Output: /work/tesseract-ec2.zip
# Built on the same OS/arch as the EC2 baseline's AMI (al2023, aarch64 for t4g.*) so the binaries and
# shared libraries just run -- no cross-glibc compatibility games needed, unlike the Lambda layer
# (which targets amazonlinux:2's older glibc for the Lambda runtime).
set -euo pipefail
TESSERACT=5.5.3
LEPTONICA=1.87.0
TESSDATA_URL=https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata

dnf -q -y install gcc-c++ make autoconf automake libtool pkgconfig autoconf-archive wget tar gzip xz zip \
  libpng-devel libjpeg-turbo-devel libtiff-devel zlib-devel python3 >/dev/null

OUT=/opt/out
mkdir -p /build && cd /build
wget -q "https://github.com/DanBloomberg/leptonica/releases/download/$LEPTONICA/leptonica-$LEPTONICA.tar.gz" -O lep.tgz
tar xf lep.tgz && cd "leptonica-$LEPTONICA"
./configure --prefix=$OUT --disable-static >/dev/null && make -j"$(nproc)" >/dev/null && make install >/dev/null
cd /build
wget -q "https://github.com/tesseract-ocr/tesseract/archive/refs/tags/$TESSERACT.tar.gz" -O tes.tgz
tar xf tes.tgz && cd "tesseract-$TESSERACT"
./autogen.sh >/dev/null 2>&1
PKG_CONFIG_PATH=$OUT/lib/pkgconfig ./configure --prefix=$OUT --disable-static --disable-openmp >/dev/null \
  && make -j"$(nproc)" >/dev/null && make install >/dev/null

mkdir -p $OUT/share/tessdata
wget -q "$TESSDATA_URL" -O $OUT/share/tessdata/eng.traineddata
# Orientation data: the reader turns sideways menus upright with tesseract --psm 0, which needs osd.
wget -q https://github.com/tesseract-ocr/tessdata_fast/raw/main/osd.traineddata -O $OUT/share/tessdata/osd.traineddata

# Shared libraries tesseract needs beyond the OS's own (glibc, libstdc++ etc. are already on the AMI).
mkdir -p $OUT/lib
for lib in $(ldd $OUT/bin/tesseract | awk '/=>/ {print $3}'); do
  case "$(basename "$lib")" in
    ld-linux*|linux-vdso*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libgcc_s.so*|libresolv.so*|libstdc++.so*) ;;
    *) cp -Ln "$lib" $OUT/lib/ 2>/dev/null || true ;;
  esac
done

strip --strip-unneeded $OUT/bin/tesseract $OUT/lib/*.so* 2>/dev/null || true

# Keep only what the reader uses: the tesseract program, not the training tools.
cd $OUT
for t in convertfilestopdf convertfilestops convertformat convertsegfilestopdf convertsegfilestops converttopdf converttops fileinfo imagetops xtractprotos; do rm -f bin/$t; done
rm -rf include lib/cmake lib/pkgconfig
find lib -name "*.la" -delete
find share/tessdata -name "*.traineddata" -not -name "eng.traineddata" -not -name "osd.traineddata" -delete 2>/dev/null || true

# zip -y keeps symlinks as links, so libtesseract.so.5 -> libtesseract.so.5.0.5 isn't stored twice.
cd $OUT && zip -qry /work/tesseract-ec2.zip .
echo "built /work/tesseract-ec2.zip"

#!/usr/bin/env bash
# Runs inside amazonlinux:2 (called by build.sh). Output: /work/tesseract-layer.zip
# Amazon Linux 2 matches the python3.11 Lambda runtime (glibc 2.26). Release tarballs ship a configure script,
# so no autotools beyond the basics are needed.
set -euo pipefail
TESSERACT=5.5.3
LEPTONICA=1.87.0
NUMPY=2.2.6        # newest numpy that runs on Lambda's Python 3.11 (the project pins 2.5.4, which needs 3.12+)
PILLOW=12.2.0
PYPDFIUM2=5.14.0
TESSDATA_URL=https://github.com/tesseract-ocr/tessdata_fast/raw/main/eng.traineddata

yum -q -y install gcc10-c++ make tar gzip wget zip xz autoconf automake libtool pkgconfig libpng-devel \
  libjpeg-turbo-devel libtiff-devel zlib-devel python3 python3-pip >/dev/null
# Tesseract 5 needs C++17 <filesystem>, which Amazon Linux 2's default gcc 7 lacks: use gcc 10.
export CC=/usr/bin/gcc10-gcc CXX=/usr/bin/gcc10-g++
# Amazon Linux 2's pip (20.2) can't resolve Python 3.11 wheels; pip 23 can.
python3 -m pip install -q -U "pip<24"
# Tesseract's source tag has no configure script: autogen.sh needs the GNU autoconf-archive macros.
wget -q https://ftp.gnu.org/gnu/autoconf-archive/autoconf-archive-2023.02.20.tar.xz -O aa.tar.xz
tar xf aa.tar.xz && (cd autoconf-archive-2023.02.20 && ./configure --prefix=/usr >/dev/null && make install >/dev/null)

OUT=/opt/out
mkdir -p /build && cd /build
wget -q "https://github.com/DanBloomberg/leptonica/releases/download/$LEPTONICA/leptonica-$LEPTONICA.tar.gz" -O lep.tgz
tar xf lep.tgz && cd "leptonica-$LEPTONICA"
./configure --prefix=$OUT --disable-static >/dev/null && make -j4 >/dev/null && make install >/dev/null
cd /build
wget -q "https://github.com/tesseract-ocr/tesseract/archive/refs/tags/$TESSERACT.tar.gz" -O tes.tgz
tar xf tes.tgz && cd "tesseract-$TESSERACT"
./autogen.sh >/dev/null 2>&1
PKG_CONFIG_PATH=$OUT/lib/pkgconfig ./configure --prefix=$OUT --disable-static --disable-openmp >/dev/null \
  && make -j4 >/dev/null && make install >/dev/null

mkdir -p $OUT/share/tessdata
wget -q "$TESSDATA_URL" -O $OUT/share/tessdata/eng.traineddata
# Orientation data: the reader turns sideways menus upright with tesseract --psm 0, which needs osd.
wget -q https://github.com/tesseract-ocr/tessdata_fast/raw/main/osd.traineddata -O $OUT/share/tessdata/osd.traineddata

python3 -m pip install -q --no-cache-dir --only-binary=:all: --platform manylinux2014_x86_64 \
  --implementation cp --python-version 3.11 --abi cp311 --ignore-requires-python --target $OUT/python \
  numpy==$NUMPY pillow==$PILLOW pypdfium2==$PYPDFIUM2

# Shared libraries tesseract needs that the Lambda base image may not have. glibc and the loader stay out.
mkdir -p $OUT/lib
for lib in $(ldd $OUT/bin/tesseract | awk '/=>/ {print $3}'); do
  case "$(basename "$lib")" in ld-linux*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libgcc_s.so*|libresolv.so*) ;;
    *) cp -Ln "$lib" $OUT/lib/ 2>/dev/null || true ;; esac
done

# Keep only what the reader uses: the tesseract program, not the training tools.
cd $OUT
for t in convertfilestopdf convertfilestops convertformat convertsegfilestopdf convertsegfilestops converttopdf converttops fileinfo imagetops xtractprotos; do rm -f bin/$t; done
rm -rf lib/cmake lib/pkgconfig
find lib -name "*.la" -delete
find . -name "__pycache__" -type d -prune -exec rm -rf {} +
find python -name "tests" -type d -prune -exec rm -rf {} +
find python -name "*.dist-info" -type d -prune -exec rm -rf {} +
find python -name "*.pyi" -delete

# zip -y keeps symlinks as links. Without it, shared libraries are stored several times and the unzipped
# size goes over Lambda's 250 MB limit.
yum -q -y install zip >/dev/null 2>&1 || true
cd $OUT && zip -qry /work/tesseract-layer.zip .
echo "built /work/tesseract-layer.zip"

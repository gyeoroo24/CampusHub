#!/usr/bin/env bash
# Runs inside amazonlinux:2 (called by build.sh). Output: /work/pg-layer.zip
# PostgreSQL 16 is built from source: Amazon Linux 2's own packages are older than the RDS server (16),
# and pg_dump refuses to dump a server newer than itself.
set -euo pipefail
PG=16.15
yum -q -y install gcc make readline-devel zlib-devel openssl-devel tar gzip wget zip >/dev/null
mkdir -p /build && cd /build
wget -q "https://ftp.postgresql.org/pub/source/v$PG/postgresql-$PG.tar.gz" -O pg.tgz
tar xf pg.tgz && cd "postgresql-$PG"
./configure --prefix=/opt/out --without-readline --without-icu --with-openssl --with-zlib --disable-rpath >/dev/null
make -C src/interfaces/libpq -j4 >/dev/null && make -C src/interfaces/libpq install >/dev/null
make -C src/bin/pg_dump -j4 >/dev/null && make -C src/bin/pg_dump install >/dev/null
make -C src/bin/psql -j4 >/dev/null && make -C src/bin/psql install >/dev/null

OUT=/opt/out
mkdir -p $OUT/bin $OUT/lib
cp -L $OUT/bin/pg_dump $OUT/bin/pg_restore $OUT/bin/psql $OUT/bin/ 2>/dev/null || true
# Shared libraries the programs need that the Lambda base image may not have. glibc and the loader stay out.
for prog in $OUT/bin/pg_dump $OUT/bin/pg_restore $OUT/bin/psql; do
  for lib in $(ldd $prog | awk '/=>/ {print $3}'); do
    case "$(basename "$lib")" in ld-linux*|libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|libgcc_s.so*|libresolv.so*) ;;
      *) cp -Ln "$lib" $OUT/lib/ 2>/dev/null || true ;; esac
  done
done
cp -Ln $OUT/lib/libpq.so.5* $OUT/lib/ 2>/dev/null || true
cd $OUT && zip -qry /work/pg-layer.zip .
echo "built /work/pg-layer.zip"

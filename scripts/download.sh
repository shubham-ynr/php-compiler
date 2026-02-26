#!/bin/bash
set -e

DEST="downloads"
mkdir -p $DEST/php $DEST/deps $DEST/pecl $DEST/toolchain

download () {
  URL=$1
  FILE=$2
  if [ -f "$FILE" ]; then
    echo "✔ $(basename $FILE) exists"
    return
  fi
  echo "⬇ Downloading $(basename $FILE)"
  curl -L --fail -o "$FILE" "$URL"
}

echo "=== Toolchain ==="
download https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.gz $DEST/toolchain/m4-1.4.19.tar.gz
download https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz $DEST/toolchain/autoconf-2.71.tar.gz
download https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.gz $DEST/toolchain/automake-1.16.5.tar.gz
download https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.gz $DEST/toolchain/libtool-2.4.7.tar.gz
download https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz $DEST/toolchain/pkg-config-0.29.2.tar.gz
download https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.gz $DEST/toolchain/bison-3.8.2.tar.gz
download https://github.com/skvadrik/re2c/releases/download/3.1/re2c-3.1.tar.gz $DEST/toolchain/re2c-3.1.tar.gz

echo "=== PHP ==="
while read V; do
  [[ -z "$V" || "$V" =~ ^# ]] && continue
  download https://www.php.net/distributions/php-$V.tar.gz $DEST/php/php-$V.tar.gz
done < versions/php-versions.txt

echo "=== PECL ==="
download https://pecl.php.net/get/redis-6.0.2.tgz $DEST/pecl/redis-6.0.2.tgz
download https://pecl.php.net/get/apcu-5.1.23.tgz $DEST/pecl/apcu-5.1.23.tgz
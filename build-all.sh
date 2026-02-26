#!/bin/bash
set -e

ROOT=$(pwd)
VERSION_FILE="versions/php-versions.txt"

DOWNLOADS="$ROOT/downloads"
PHP_SRC="$DOWNLOADS/php"
DEPS_SRC="$DOWNLOADS/deps"
PECL_SRC="$DOWNLOADS/pecl"
DB_SRC="$DOWNLOADS/db"
TOOLCHAIN_SRC="$DOWNLOADS/toolchain"

LOCAL_DEPS="$ROOT/local-deps"
LOCAL_TOOLCHAIN="$ROOT/local-toolchain"

mkdir -p "$PHP_SRC" "$DEPS_SRC" "$PECL_SRC" "$DB_SRC" "$TOOLCHAIN_SRC"
mkdir -p "$LOCAL_DEPS" "$LOCAL_TOOLCHAIN"

############################################
# DOWNLOAD HELPER
############################################
download() {
  URL=$1
  TARGET=$2
  if [ -f "$TARGET" ]; then
    echo "✔ $(basename $TARGET) exists"
    return
  fi
  echo "⬇ Downloading $(basename $TARGET)"
  curl -L --fail -o "$TARGET" "$URL"
}

############################################
# DOWNLOAD PHASE
############################################
echo "=== DOWNLOAD PHASE ==="

# CORE DEPS
download https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz \
  "$DEPS_SRC/zlib-1.3.tar.gz"

download https://www.openssl.org/source/openssl-3.2.1.tar.gz \
  "$DEPS_SRC/openssl-3.2.1.tar.gz"

download https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz \
  "$DEPS_SRC/icu4c-74_2-src.tgz"

download https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz \
  "$DEPS_SRC/onig-6.9.9.tar.gz"

download https://libzip.org/download/libzip-1.10.1.tar.gz \
  "$DEPS_SRC/libzip-1.10.1.tar.gz"

# TOOLCHAIN
download https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.gz \
  "$TOOLCHAIN_SRC/m4-1.4.19.tar.gz"

download https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz \
  "$TOOLCHAIN_SRC/autoconf-2.71.tar.gz"

download https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.gz \
  "$TOOLCHAIN_SRC/automake-1.16.5.tar.gz"

download https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.gz \
  "$TOOLCHAIN_SRC/libtool-2.4.7.tar.gz"

download https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz \
  "$TOOLCHAIN_SRC/pkg-config-0.29.2.tar.gz"

download https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.gz \
  "$TOOLCHAIN_SRC/bison-3.8.2.tar.gz"

download https://github.com/skvadrik/re2c/releases/download/3.1/re2c-3.1.tar.xz \
  "$TOOLCHAIN_SRC/re2c-3.1.tar.xz"

# PECL
download https://pecl.php.net/get/apcu-5.1.23.tgz \
  "$PECL_SRC/apcu-5.1.23.tgz"

download https://pecl.php.net/get/redis-6.0.2.tgz \
  "$PECL_SRC/redis-6.0.2.tgz"

download https://pecl.php.net/get/xdebug-3.3.2.tgz \
  "$PECL_SRC/xdebug-3.3.2.tgz"

# PHP
while read V; do
  [[ -z "$V" || "$V" =~ ^# ]] && continue
  download https://www.php.net/distributions/php-$V.tar.gz \
    "$PHP_SRC/php-$V.tar.gz"
done < "$VERSION_FILE"

############################################
# BUILD TOOLCHAIN
############################################
echo "=== BUILD TOOLCHAIN ==="

export PATH="$LOCAL_TOOLCHAIN/bin:$PATH"

build_tool() {
  FILE=$1
  NAME=$(basename $FILE)
  NAME=${NAME%.tar.gz}
  NAME=${NAME%.tar.xz}

  rm -rf build-$NAME
  mkdir build-$NAME
  cd build-$NAME

  tar -xf "$TOOLCHAIN_SRC/$FILE" --strip-components=1
  ./configure --prefix="$LOCAL_TOOLCHAIN"
  make -j$(sysctl -n hw.ncpu)
  make install
  cd ..
}

build_tool m4-1.4.19.tar.gz
build_tool autoconf-2.71.tar.gz
build_tool automake-1.16.5.tar.gz
build_tool libtool-2.4.7.tar.gz
build_tool pkg-config-0.29.2.tar.gz
build_tool bison-3.8.2.tar.gz
build_tool re2c-3.1.tar.xz

############################################
# BUILD PHP
############################################
echo "=== BUILD PHP ==="

while read V; do
  [[ -z "$V" || "$V" =~ ^# ]] && continue

  echo ">>> Building PHP $V"

  PREFIX="$ROOT/output-$V/php-$V-arm64"
  mkdir -p "$PREFIX"

  rm -rf build-php
  mkdir build-php
  cd build-php

  tar -xf "$PHP_SRC/php-$V.tar.gz" --strip-components=1

  ./configure \
    --prefix="$PREFIX" \
    --enable-cli \
    --enable-fpm \
    --enable-opcache \
    --disable-opcache-jit \
    --enable-mbstring \
    --enable-intl \
    --enable-mysqlnd \
    --with-zlib \
    --with-openssl \
    --with-iconv \
    --without-pear

  make -j$(sysctl -n hw.ncpu)
  make install

  cd ..

  ##########################################
  # PECL BUILD
  ##########################################
  export PATH="$PREFIX/bin:$PATH"

  for FILE in $PECL_SRC/*.tgz; do
    tar -xf "$FILE"
    DIR=$(tar -tf "$FILE" | head -1 | cut -d"/" -f1)
    cd "$DIR"

    phpize
    ./configure --with-php-config="$PREFIX/bin/php-config"
    make -j$(sysctl -n hw.ncpu)
    make install

    EXT=$(basename "$FILE" .tgz | cut -d- -f1)
    echo "extension=$EXT.so" >> "$PREFIX/lib/php.ini"

    cd ..
    rm -rf "$DIR"
  done

done < "$VERSION_FILE"

echo "=================================="
echo "✅ ALL BUILDS COMPLETE"
echo "=================================="
#!/bin/bash
set -e

ROOT=$(pwd)
VERSION_FILE="versions/php-versions.txt"

DOWNLOADS="$ROOT/downloads"
PHP_SRC="$DOWNLOADS/php"
DEPS_SRC="$DOWNLOADS/deps"
PECL_SRC="$DOWNLOADS/pecl"
TOOLCHAIN_SRC="$DOWNLOADS/toolchain"

LOCAL_DEPS="$ROOT/local-deps"
LOCAL_TOOLCHAIN="$ROOT/local-toolchain"

mkdir -p "$PHP_SRC" "$DEPS_SRC" "$PECL_SRC" "$TOOLCHAIN_SRC"
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
# DOWNLOAD STATIC DEPS (ONCE)
############################################
echo "=== Downloading Dependencies ==="

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

download https://github.com/skvadrik/re2c/releases/download/3.1/re2c-3.1.tar.xz \
  "$TOOLCHAIN_SRC/re2c-3.1.tar.xz"

############################################
# BUILD CORE DEPS
############################################
echo "=== Building Core Dependencies ==="

export PATH="$LOCAL_TOOLCHAIN/bin:$PATH"
export PKG_CONFIG_PATH="$LOCAL_DEPS/lib/pkgconfig"

build_dep() {
  FILE=$1
  NAME=$(basename $FILE)
  NAME=${NAME%.tar.gz}
  NAME=${NAME%.tgz}
  NAME=${NAME%.tar.xz}

  rm -rf build-$NAME
  mkdir build-$NAME
  cd build-$NAME

  tar -xf "$DEPS_SRC/$FILE" --strip-components=1 || \
  tar -xf "$TOOLCHAIN_SRC/$FILE" --strip-components=1

  ./configure --prefix="$LOCAL_DEPS" || true
  make -j$(sysctl -n hw.ncpu)
  make install
  cd ..
}

build_dep zlib-1.3.tar.gz
build_dep onig-6.9.9.tar.gz
build_dep libzip-1.10.1.tar.gz

############################################
# BUILD PHP PER VERSION (LAZY DOWNLOAD)
############################################
echo "=== Building PHP Versions ==="

while read V; do
  [[ -z "$V" || "$V" =~ ^# ]] && continue

  FILE="php-$V.tar.gz"
  TARGET="$PHP_SRC/$FILE"

  ########################################
  # Lazy Download Per Version
  ########################################
  if [ ! -f "$TARGET" ]; then
    echo "⬇ Downloading PHP $V"
    MAIN_URL="https://www.php.net/distributions/$FILE"
    ARCHIVE_URL="https://museum.php.net/php${V%.*}/$FILE"

    if curl -L --fail -o "$TARGET" "$MAIN_URL"; then
      echo "✔ Main mirror"
    else
      echo "Main failed → Archive"
      curl -L --fail -o "$TARGET" "$ARCHIVE_URL"
    fi
  fi

  ########################################
  # Build PHP
  ########################################
  PREFIX="$ROOT/output-$V/php-$V-arm64"
  mkdir -p "$PREFIX"

  rm -rf build-php
  mkdir build-php
  cd build-php

  tar -xf "$TARGET" --strip-components=1

  ./configure \
    --prefix="$PREFIX" \
    --with-config-file-path="$PREFIX/etc" \
    --with-zlib="$LOCAL_DEPS" \
    --with-openssl="$LOCAL_DEPS" \
    --with-iconv \
    --enable-cli \
    --enable-fpm \
    --enable-opcache \
    --disable-opcache-jit \
    --enable-mbstring \
    --enable-intl \
    --enable-mysqlnd \
    --without-pear

  make -j$(sysctl -n hw.ncpu)
  make install
  cd ..

  ########################################
  # PECL INSTALL
  ########################################
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
    echo "extension=$EXT.so" >> "$PREFIX/etc/php.ini"

    cd ..
    rm -rf "$DIR"
  done

done < "$VERSION_FILE"

echo "=================================="
echo "✅ ALL BUILDS COMPLETE"
echo "=================================="
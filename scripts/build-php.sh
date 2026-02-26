#!/bin/bash
set -e

VERSION=$1
ARCH="arm64"

if [ -z "$VERSION" ]; then
  echo "❌ Provide PHP version"
  exit 1
fi

ROOT="$(pwd)/output-$VERSION"
SRC="$ROOT/src"
PREFIX="$ROOT/local"
FINAL="$ROOT/php-$VERSION-$ARCH"

CPU=$(sysctl -n hw.ncpu)

mkdir -p "$SRC"
mkdir -p "$PREFIX"

PHP_TARBALL="downloads/php/php-$VERSION.tar.gz"

if [ ! -f "$PHP_TARBALL" ]; then
  echo "❌ Missing $PHP_TARBALL"
  exit 1
fi

cd "$SRC"

########################################
# BUILD ZLIB
########################################
echo "📦 Building zlib"
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/zlib-1.3.tar.gz"
cd zlib-1.3
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ..

########################################
# BUILD ONIGURUMA
########################################
echo "📦 Building Oniguruma"
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/onig-6.9.9.tar.gz"
cd onig-6.9.9
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ..

########################################
# BUILD OPENSSL
########################################
echo "📦 Building OpenSSL"
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/openssl-3.2.1.tar.gz"
cd openssl-3.2.1
./Configure darwin64-arm64-cc --prefix="$PREFIX"
make -j$CPU
make install_sw
cd ..

########################################
# BUILD ICU
########################################
echo "📦 Building ICU"
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/icu4c-74_2-src.tgz"
cd icu/source
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ../..

########################################
# BUILD PHP
########################################
echo "⚙ Building PHP $VERSION"

tar -xzf "$GITHUB_WORKSPACE/$PHP_TARBALL"
cd "php-$VERSION"

export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

./configure \
  --prefix="$FINAL" \
  --enable-cli \
  --enable-fpm \
  --enable-opcache \
  --enable-mbstring \
  --enable-intl \
  --enable-bcmath \
  --enable-pcntl \
  --enable-sockets \
  --enable-calendar \
  --enable-exif \
  --enable-fileinfo \
  --enable-filter \
  --enable-session \
  --enable-tokenizer \
  --enable-xml \
  --with-zlib="$PREFIX" \
  --with-openssl="$PREFIX" \
  --with-icu-dir="$PREFIX" \
  --with-onig="$PREFIX" \
  --with-sqlite3 \
  --with-mysqli=mysqlnd \
  --with-pdo-mysql=mysqlnd

make -j$CPU
make install

########################################
# PACKAGE
########################################
cd "$ROOT"
zip -r "php-$VERSION-$ARCH.zip" "php-$VERSION-$ARCH"

echo "✅ PHP $VERSION ARM64 build complete"
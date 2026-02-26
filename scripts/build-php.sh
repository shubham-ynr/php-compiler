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

########################################
# VERIFY SOURCE
########################################

PHP_TARBALL="downloads/php/php-$VERSION.tar.gz"

if [ ! -f "$PHP_TARBALL" ]; then
  echo "❌ Missing $PHP_TARBALL"
  exit 1
fi

########################################
# BUILD DEPENDENCIES
########################################

cd "$SRC"

build_shared() {
  FILE=$1
  DIR=$2

  cp "$GITHUB_WORKSPACE/downloads/deps/$FILE" .
  tar -xf "$FILE"
  cd "$DIR"
  ./configure --prefix="$PREFIX" --enable-shared --disable-static
  make -j$CPU
  make install
  cd ..
}

echo "📦 Building zlib"
build_shared zlib-1.3.tar.gz zlib-1.3

echo "📦 Building Oniguruma"
build_shared onig-6.9.9.tar.gz onig-6.9.9

echo "📦 Building OpenSSL"
cp "$GITHUB_WORKSPACE/downloads/deps/openssl-3.2.1.tar.gz" .
tar -xzf openssl-3.2.1.tar.gz
cd openssl-3.2.1
./Configure darwin64-arm64-cc shared no-tests --prefix="$PREFIX"
make -j$CPU
make install_sw
cd ..

echo "📦 Building ICU"
cp "$GITHUB_WORKSPACE/downloads/deps/icu4c-74_2-src.tgz" .
tar -xzf icu4c-74_2-src.tgz
cd icu/source
./configure --prefix="$PREFIX" --enable-shared --disable-static
make -j$CPU
make install
cd ../..

########################################
# BUILD PHP
########################################

echo "⚙ Building PHP $VERSION"

cp "$GITHUB_WORKSPACE/$PHP_TARBALL" .
tar -xzf "php-$VERSION.tar.gz"
cd "php-$VERSION"

export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,@loader_path/../lib"
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
  --with-zlib="$PREFIX" \
  --with-openssl="$PREFIX" \
  --with-icu-dir="$PREFIX" \
  --with-onig="$PREFIX" \
  --with-sqlite3 \
  --disable-static

make -j$CPU
make install

########################################
# ZIP
########################################

cd "$ROOT"
zip -r "php-$VERSION-$ARCH.zip" "php-$VERSION-$ARCH"

echo "✅ Build complete"
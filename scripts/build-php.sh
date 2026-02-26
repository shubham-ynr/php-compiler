#!/bin/bash
set -e

PHP_VERSION=$1
ARCH=arm64

if [ -z "$PHP_VERSION" ]; then
  echo "Usage: ./build-php.sh <php-version>"
  exit 1
fi

ROOT="$PWD/output-$PHP_VERSION"
SRC="$ROOT/src"
PREFIX="$ROOT/local"
PHP_PREFIX="$ROOT/php-$PHP_VERSION-$ARCH"

CPU=$(sysctl -n hw.ncpu)

rm -rf "$ROOT"
mkdir -p "$SRC" "$PREFIX"

############################################
# GLOBAL FLAGS
############################################
export CFLAGS="-arch $ARCH -mmacosx-version-min=11.0"
export CXXFLAGS="$CFLAGS"
export LDFLAGS="-arch $ARCH -mmacosx-version-min=11.0"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

cd "$SRC"

download() {
  curl -L --fail -o "$2" "$1"
}

############################################
# ZLIB
############################################
download https://zlib.net/zlib-1.3.tar.gz zlib.tar.gz
tar -xzf zlib.tar.gz
cd zlib-1.3
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ..

############################################
# OpenSSL
############################################
download https://www.openssl.org/source/openssl-3.2.1.tar.gz openssl.tar.gz
tar -xzf openssl.tar.gz
cd openssl-3.2.1
./Configure darwin64-arm64-cc shared no-tests --prefix="$PREFIX"
make -j$CPU
make install_sw
cd ..

############################################
# ICU
############################################
download https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz icu.tgz
tar -xzf icu.tgz
cd icu/source
./configure --prefix="$PREFIX" --enable-shared --disable-static
make -j$CPU
make install
cd ../..

############################################
# Oniguruma
############################################
download https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz onig.tar.gz
tar -xzf onig.tar.gz
cd onig-6.9.9
./configure --prefix="$PREFIX" --enable-shared --disable-static
make -j$CPU
make install
cd ..

############################################
# PHP
############################################
download https://www.php.net/distributions/php-$PHP_VERSION.tar.gz php.tar.gz
tar -xzf php.tar.gz
cd php-$PHP_VERSION

export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,@loader_path/../../local/lib"

./configure \
  --prefix="$PHP_PREFIX" \
  --with-config-file-path="$PHP_PREFIX/etc" \
  --with-config-file-scan-dir="$PHP_PREFIX/etc/conf.d" \
  --enable-cli \
  --enable-fpm \
  --enable-opcache \
  --enable-mbstring \
  --enable-intl \
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

mkdir -p "$PHP_PREFIX/etc/conf.d"
cp php.ini-production "$PHP_PREFIX/etc/php.ini"

############################################
# RPATH FIX
############################################
install_name_tool -add_rpath @loader_path/../../local/lib "$PHP_PREFIX/bin/php"
install_name_tool -add_rpath @loader_path/../../local/lib "$PHP_PREFIX/sbin/php-fpm"

############################################
# PECL
############################################
export PATH="$PHP_PREFIX/bin:$PATH"

yes '' | pecl install apcu
yes '' | pecl install redis
yes '' | pecl install xdebug

echo "extension=apcu.so" >> "$PHP_PREFIX/etc/php.ini"
echo "extension=redis.so" >> "$PHP_PREFIX/etc/php.ini"
echo "zend_extension=xdebug.so" >> "$PHP_PREFIX/etc/php.ini"

echo "======================================"
echo "✅ PHP $PHP_VERSION ARM64 BUILD DONE"
echo "======================================"
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
# BUILD LIBICONV
########################################
curl -L -o libiconv.tar.gz https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz
tar -xzf libiconv.tar.gz
cd libiconv-1.17
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ..

########################################
# BUILD ZLIB
########################################
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/zlib-1.3.tar.gz"
cd zlib-1.3
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ..

########################################
# BUILD ONIGURUMA
########################################
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/onig-6.9.9.tar.gz"
cd onig-6.9.9
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ..

########################################
# BUILD OPENSSL
########################################
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/openssl-3.2.1.tar.gz"
cd openssl-3.2.1
./Configure darwin64-arm64-cc --prefix="$PREFIX"
make -j$CPU
make install_sw
cd ..

########################################
# BUILD ICU
########################################
tar -xzf "$GITHUB_WORKSPACE/downloads/deps/icu4c-74_2-src.tgz"
cd icu/source
./configure --prefix="$PREFIX"
make -j$CPU
make install
cd ../..

########################################
# BUILD PHP CORE (NO OPCACHE)
########################################
tar -xzf "$GITHUB_WORKSPACE/$PHP_TARBALL"
cd "php-$VERSION"

unset CFLAGS
unset CPPFLAGS
unset LDFLAGS
unset LIBS

export CPPFLAGS="-I$PREFIX/include"
export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
export DYLD_LIBRARY_PATH="$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"

# DNS resolver fix
export LIBS="-lresolv"

./configure \
  --prefix="$FINAL" \
  --enable-cli \
  --enable-fpm \
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
  --disable-opcache \
  --with-zlib="$PREFIX" \
  --with-openssl="$PREFIX" \
  --with-icu-dir="$PREFIX" \
  --with-onig="$PREFIX" \
  --with-iconv="$PREFIX" \
  --with-sqlite3 \
  --with-mysqli=mysqlnd \
  --with-pdo-mysql=mysqlnd

make -j$CPU
make install

########################################
# Inject rpath manually (extra safety)
########################################
install_name_tool -add_rpath "$PREFIX/lib" "$FINAL/bin/php" || true

########################################
# BUILD OPCACHE SEPARATELY
########################################
cd ext/opcache

"$FINAL/bin/phpize"

./configure \
  --with-php-config="$FINAL/bin/php-config" \
  --disable-huge-code-pages \
  --disable-opcache-jit

make -j$CPU
make install

########################################
# CREATE php.ini
########################################
mkdir -p "$FINAL/lib"

cat > "$FINAL/lib/php.ini" <<EOF
zend_extension=opcache

opcache.enable=1
opcache.enable_cli=1
opcache.memory_consumption=128
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=10000
opcache.revalidate_freq=0
opcache.save_comments=1
opcache.jit=0
opcache.file_cache=/tmp/php-opcache
EOF

########################################
# VERIFY
########################################
echo "Testing PHP..."
"$FINAL/bin/php" -v
"$FINAL/bin/php" -m | grep -i opcache || true

########################################
# PACKAGE
########################################
cd "$ROOT"
zip -r "php-$VERSION-$ARCH.zip" "php-$VERSION-$ARCH"

echo ""
echo "✅ PHP $VERSION ARM64 build complete with OPcache"
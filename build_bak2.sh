#!/bin/bash
set -e

############################################
# BASIC CONFIG
############################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$SCRIPT_DIR"

VERSION=$1
ARCH="arm64"
CPU=$(sysctl -n hw.ncpu)

if [ -z "$VERSION" ]; then
  echo "Usage: ./build.sh 8.1.7"
  exit 1
fi

############################################
# CACHE STRUCTURE
############################################
CACHE="$WORK/.cache"
DEPS="$CACHE/deps"
SRC="$CACHE/src"

mkdir -p "$DEPS"
mkdir -p "$SRC"

############################################
# DOWNLOAD HELPER
############################################
download() {
  URL=$1
  FILE=$2
  if [ ! -f "$FILE" ]; then
    echo "⬇ Downloading $(basename "$FILE")"
    curl -L --fail -o "$FILE" "$URL"
  fi
}

############################################
# BUILD DEPENDENCIES (ONCE)
############################################
if [ ! -f "$DEPS/lib/libicuuc.a" ]; then

  echo "🔧 Building global dependencies..."

  cd "$SRC"

  # LIBICONV (STATIC)
  download https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz iconv.tar.gz
  tar -xzf iconv.tar.gz
  cd libiconv-1.17
  ./configure --prefix="$DEPS" --enable-static --disable-shared
  make -j$CPU && make install
  cd ..

  # ZLIB
  download https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz zlib.tar.gz
  tar -xzf zlib.tar.gz
  cd zlib-1.3
  ./configure --prefix="$DEPS"
  make -j$CPU && make install
  cd ..

  # OPENSSL (dynamic but relocatable)
  download https://www.openssl.org/source/openssl-3.2.1.tar.gz openssl.tar.gz
  tar -xzf openssl.tar.gz
  cd openssl-3.2.1
  ./Configure darwin64-arm64-cc --prefix="$DEPS"
  make -j$CPU && make install_sw
  cd ..

  # ONIGURUMA
  download https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz onig.tar.gz
  tar -xzf onig.tar.gz
  cd onig-6.9.9
  ./configure --prefix="$DEPS"
  make -j$CPU && make install
  cd ..

  # ICU (STATIC ONLY)
  download https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz icu.tgz
  tar -xzf icu.tgz
  cd icu/source
  ./configure --prefix="$DEPS" --enable-static --disable-shared
  make -j$CPU && make install
  cd ../..

fi

############################################
# BUILD PHP
############################################
cd "$SRC"

download https://www.php.net/distributions/php-$VERSION.tar.gz php.tar.gz
rm -rf php-$VERSION
tar -xzf php.tar.gz
cd php-$VERSION

unset CFLAGS CPPFLAGS LDFLAGS LIBS

export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig"
export LIBS="-lresolv"

FINAL="$WORK/php-$VERSION-$ARCH"

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
  --with-zlib="$DEPS" \
  --with-openssl="$DEPS" \
  --with-icu-dir="$DEPS" \
  --with-onig="$DEPS" \
  --with-iconv="$DEPS" \
  --with-sqlite3 \
  --with-mysqli=mysqlnd \
  --with-pdo-mysql=mysqlnd \
  --enable-shared \
  --with-pear

make -j$CPU
make install

############################################
# FIX OPENSSL PATHS (PORTABLE)
############################################
echo "🔧 Fixing OpenSSL linkage..."

BIN="$FINAL/bin/php"
LIBDIR="$FINAL/lib"

mkdir -p "$LIBDIR"

for lib in libssl.3.dylib libcrypto.3.dylib libz.1.dylib libonig.5.dylib; do
  if [ -f "$DEPS/lib/$lib" ]; then
    cp "$DEPS/lib/$lib" "$LIBDIR/"
    install_name_tool -id "@rpath/$lib" "$LIBDIR/$lib"
    install_name_tool -change "$DEPS/lib/$lib" "@rpath/$lib" "$BIN"
  fi
done

if ! otool -l "$BIN" | grep -q "@executable_path/../lib"; then
  install_name_tool -add_rpath "@executable_path/../lib" "$BIN"
fi

############################################
# HARD VALIDATION
############################################
echo "🔎 Validating binary..."

if otool -L "$BIN" | grep -q "/Users/runner"; then
  echo "❌ Runner path detected — build aborted"
  exit 1
fi

echo "✅ Binary clean"

############################################
# CREATE php.ini
############################################
mkdir -p "$FINAL/lib"

cat > "$FINAL/lib/php.ini" <<EOF
zend_extension=opcache
opcache.enable=1
opcache.enable_cli=1
opcache.jit=0
EOF

############################################
# PACKAGE
############################################
cd "$WORK"
zip -r "php-$VERSION-$ARCH.zip" "php-$VERSION-$ARCH"

echo ""
echo "======================================"
echo "✅ PHP $VERSION built successfully"
echo "ICU = STATIC"
echo "ICONV = STATIC"
echo "OPENSSL = PORTABLE DYNAMIC"
echo "======================================"
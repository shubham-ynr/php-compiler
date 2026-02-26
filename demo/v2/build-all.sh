#!/bin/bash
set -e

ARCH="arm64"
CPU=$(sysctl -n hw.ncpu)
WORK="$(pwd)"
VERSIONS_FILE="versions/php-versions.txt"

############################################
# DOWNLOAD HELPER
############################################
download() {
  URL=$1
  FILE=$2

  if [ -f "$FILE" ]; then
    echo "✔ $(basename $FILE) exists"
    return
  fi

  echo "⬇ Downloading $(basename $FILE)"
  curl -L --fail -o "$FILE" "$URL"
}

############################################
# LOCAL AUTOCONF (FOR PHPIZE)
############################################
TOOLCHAIN="$WORK/toolchain"
mkdir -p "$TOOLCHAIN"

if [ ! -f "$TOOLCHAIN/bin/autoconf" ]; then
  echo "🔧 Building local autoconf..."

  cd "$WORK"
  download https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz autoconf.tar.gz
  tar -xzf autoconf.tar.gz
  cd autoconf-2.71
  ./configure --prefix="$TOOLCHAIN"
  make -j$CPU
  make install
  cd "$WORK"
fi

export PATH="$TOOLCHAIN/bin:$PATH"

############################################
# LOOP ALL PHP VERSIONS
############################################
while read VERSION; do
  [[ -z "$VERSION" || "$VERSION" =~ ^# ]] && continue

  echo "======================================"
  echo "🚀 BUILDING PHP $VERSION"
  echo "======================================"

  ROOT="$WORK/output-$VERSION"
  SRC="$ROOT/src"
  PREFIX="$ROOT/local"
  FINAL="$ROOT/php-$VERSION-$ARCH"

  mkdir -p "$SRC" "$PREFIX"
  cd "$SRC"

  ########################################
  # DOWNLOAD DEPENDENCIES
  ########################################
  download https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz libiconv.tar.gz
  download https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz zlib.tar.gz
  download https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz onig.tar.gz
  download https://www.openssl.org/source/openssl-3.2.1.tar.gz openssl.tar.gz
  download https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz icu.tgz

  ########################################
  # BUILD LIBICONV
  ########################################
  tar -xzf libiconv.tar.gz
  cd libiconv-1.17
  ./configure --prefix="$PREFIX"
  make -j$CPU
  make install
  cd ..

  ########################################
  # BUILD ZLIB
  ########################################
  tar -xzf zlib.tar.gz
  cd zlib-1.3
  ./configure --prefix="$PREFIX"
  make -j$CPU
  make install
  cd ..

  ########################################
  # BUILD ONIGURUMA
  ########################################
  tar -xzf onig.tar.gz
  cd onig-6.9.9
  ./configure --prefix="$PREFIX"
  make -j$CPU
  make install
  cd ..

  ########################################
  # BUILD OPENSSL
  ########################################
  tar -xzf openssl.tar.gz
  cd openssl-3.2.1
  ./Configure darwin64-arm64-cc --prefix="$PREFIX"
  make -j$CPU
  make install_sw
  cd ..

  ########################################
  # BUILD ICU
  ########################################
  tar -xzf icu.tgz
  cd icu/source
  ./configure --prefix="$PREFIX"
  make -j$CPU
  make install
  cd ../..

  ########################################
  # DOWNLOAD PHP
  ########################################
  PHP_FILE="php-$VERSION.tar.gz"
  download https://www.php.net/distributions/$PHP_FILE $PHP_FILE

  ########################################
  # BUILD PHP CORE (NO OPCACHE)
  ########################################
  tar -xzf $PHP_FILE
  cd php-$VERSION

  unset CFLAGS CPPFLAGS LDFLAGS LIBS

  export CPPFLAGS="-I$PREFIX/include"
  export LDFLAGS="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
  export DYLD_LIBRARY_PATH="$PREFIX/lib"
  export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
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
opcache.jit=0
EOF

  ########################################
  # VERIFY
  ########################################
  "$FINAL/bin/php" -v
  "$FINAL/bin/php" -m | grep opcache || true

  ########################################
  # PACKAGE
  ########################################
  cd "$ROOT"
  zip -r "php-$VERSION-$ARCH.zip" "php-$VERSION-$ARCH"

  cd "$WORK"

done < "$VERSIONS_FILE"

echo "======================================"
echo "✅ ALL BUILDS COMPLETED SUCCESSFULLY"
echo "======================================"
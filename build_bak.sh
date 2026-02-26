#!/bin/bash
set -e

VERSION=$1
ARCH="arm64"
CPU=$(sysctl -n hw.ncpu)
WORK="$(pwd)"

if [ -z "$VERSION" ]; then
  echo "Usage: ./build.sh 8.1.6"
  exit 1
fi

############################################
# GLOBAL CACHE
############################################
GLOBAL_DEPS="$WORK/.global-deps"
TOOLCHAIN="$WORK/.toolchain"

mkdir -p "$GLOBAL_DEPS"
mkdir -p "$TOOLCHAIN"

############################################
# DOWNLOAD FUNCTION
############################################
download() {
  URL=$1
  FILE=$2
  if [ ! -f "$FILE" ]; then
    echo "⬇ Downloading $(basename $FILE)"
    curl -L --fail -o "$FILE" "$URL"
  fi
}

############################################
# BUILD AUTOCONF (FOR PHPIZE)
############################################
if [ ! -f "$TOOLCHAIN/bin/autoconf" ]; then
  echo "🔧 Building autoconf..."
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
# BUILD GLOBAL DEPENDENCIES (ONLY ONCE)
############################################
if [ ! -f "$GLOBAL_DEPS/lib/libz.a" ]; then

  echo "🔧 Building global dependencies..."

  cd "$WORK"

  # libiconv
  download https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz libiconv.tar.gz
  tar -xzf libiconv.tar.gz
  cd libiconv-1.17
  ./configure --prefix="$GLOBAL_DEPS"
  make -j$CPU && make install
  cd ..

  # zlib
  download https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz zlib.tar.gz
  tar -xzf zlib.tar.gz
  cd zlib-1.3
  ./configure --prefix="$GLOBAL_DEPS"
  make -j$CPU && make install
  cd ..

  # oniguruma
  download https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz onig.tar.gz
  tar -xzf onig.tar.gz
  cd onig-6.9.9
  ./configure --prefix="$GLOBAL_DEPS"
  make -j$CPU && make install
  cd ..

  # openssl
  download https://www.openssl.org/source/openssl-3.2.1.tar.gz openssl.tar.gz
  tar -xzf openssl.tar.gz
  cd openssl-3.2.1
  ./Configure darwin64-arm64-cc --prefix="$GLOBAL_DEPS"
  make -j$CPU && make install_sw
  cd ..

  # ICU
  download https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz icu.tgz
  tar -xzf icu.tgz
  cd icu/source
  ./configure --prefix="$GLOBAL_DEPS"
  make -j$CPU && make install
  cd ../..

fi

############################################
# BUILD PHP
############################################
ROOT="$WORK/output-$VERSION"
FINAL="$ROOT/php-$VERSION-$ARCH"

mkdir -p "$ROOT"

download https://www.php.net/distributions/php-$VERSION.tar.gz php.tar.gz
tar -xzf php.tar.gz
cd php-$VERSION

unset CFLAGS CPPFLAGS LDFLAGS LIBS

export CPPFLAGS="-I$GLOBAL_DEPS/include"
export LDFLAGS="-L$GLOBAL_DEPS/lib"
export DYLD_LIBRARY_PATH="$GLOBAL_DEPS/lib"
export PKG_CONFIG_PATH="$GLOBAL_DEPS/lib/pkgconfig"
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
  --with-zlib="$GLOBAL_DEPS" \
  --with-openssl="$GLOBAL_DEPS" \
  --with-icu-dir="$GLOBAL_DEPS" \
  --with-onig="$GLOBAL_DEPS" \
  --with-iconv="$GLOBAL_DEPS" \
  --with-sqlite3 \
  --with-mysqli=mysqlnd \
  --with-pdo-mysql=mysqlnd

make -j$CPU
make install

############################################
# COPY ALL DYLIBS
############################################
mkdir -p "$FINAL/lib"
cp "$GLOBAL_DEPS/lib/"*.dylib "$FINAL/lib/" || true

############################################
# FIX INSTALL NAMES (FULL ICU SAFE)
############################################
echo "🔧 Fixing dylib install names..."

# Fix self IDs
for lib in "$FINAL"/lib/*.dylib; do
    base=$(basename "$lib")
    install_name_tool -id "@rpath/$base" "$lib"
done

# Fix inter-dependencies
for lib in "$FINAL"/lib/*.dylib; do
    for dep in "$FINAL"/lib/*.dylib; do
        depbase=$(basename "$dep")
        install_name_tool -change "$GLOBAL_DEPS/lib/$depbase" "@rpath/$depbase" "$lib" 2>/dev/null || true
    done
done

# Fix php binary references
for dep in "$FINAL"/lib/*.dylib; do
    depbase=$(basename "$dep")
    install_name_tool -change "$GLOBAL_DEPS/lib/$depbase" "@rpath/$depbase" "$FINAL/bin/php" 2>/dev/null || true
done

install_name_tool -add_rpath "@loader_path/../lib" "$FINAL/bin/php" 2>/dev/null || true

############################################
# BUILD OPCACHE
############################################
cd ext/opcache
"$FINAL/bin/phpize"

./configure \
  --with-php-config="$FINAL/bin/php-config" \
  --disable-huge-code-pages \
  --disable-opcache-jit

make -j$CPU
make install

############################################
# php.ini
############################################
mkdir -p "$FINAL/lib"

cat > "$FINAL/lib/php.ini" <<EOF
zend_extension=opcache
opcache.enable=1
opcache.enable_cli=1
opcache.jit=0
EOF

############################################
# VERIFY
############################################
echo "🔎 Verifying..."
"$FINAL/bin/php" -v

############################################
# PACKAGE
############################################
cd "$ROOT"
zip -r "php-$VERSION-$ARCH.zip" "php-$VERSION-$ARCH"

echo ""
echo "✅ PHP $VERSION ARM64 portable build complete"
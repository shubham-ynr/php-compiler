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

FINAL_OUT_DIR="$WORK/output-$VERSION"
mkdir -p "$FINAL_OUT_DIR"

CACHE="$WORK/.global-deps"
DEPS="$CACHE/deps"
SRC="$CACHE/src"
mkdir -p "$DEPS" "$SRC"

############################################
# DOWNLOAD HELPER
############################################
download() {
  local URL=$1
  local FILE=$2
  if [ ! -f "$FILE" ]; then
    echo "⬇ Downloading $(basename "$FILE")"
    curl -L --fail -o "$FILE" "$URL"
  fi
}

############################################
# BUILD DEPENDENCIES
############################################
if [ ! -f "$DEPS/lib/libicuuc.a" ]; then
  echo "🔧 Building global dependencies..."
  cd "$SRC"

  # LIBICONV
  download "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz" "iconv.tar.gz"
  tar -xzf iconv.tar.gz && cd libiconv-1.17
  ./configure --prefix="$DEPS" --enable-static --disable-shared
  make -j$CPU && make install
  cd ..

  # ZLIB
  download "https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz" "zlib.tar.gz"
  tar -xzf zlib.tar.gz && cd zlib-1.3
  ./configure --prefix="$DEPS"
  make -j$CPU && make install
  cd ..

  # OPENSSL
  download "https://www.openssl.org/source/openssl-3.2.1.tar.gz" "openssl.tar.gz"
  tar -xzf openssl.tar.gz && cd openssl-3.2.1
  ./Configure darwin64-arm64-cc --prefix="$DEPS"
  make -j$CPU && make install_sw
  cd ..

  # ONIGURUMA
  download "https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz" "onig.tar.gz"
  tar -xzf onig.tar.gz && cd onig-6.9.9
  ./configure --prefix="$DEPS"
  make -j$CPU && make install
  cd ..

  # ICU
  download "https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz" "icu.tgz"
  tar -xzf icu.tgz && cd icu/source
  ./configure --prefix="$DEPS" --enable-static --disable-shared
  make -j$CPU && make install
  cd ../..
fi

############################################
# BUILD PHP
############################################
cd "$SRC"
download "https://www.php.net/distributions/php-$VERSION.tar.gz" "php.tar.gz"
rm -rf "php-$VERSION"
tar -xzf php.tar.gz
cd "php-$VERSION"

unset CFLAGS CPPFLAGS LDFLAGS LIBS
export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig"
export LIBS="-lresolv"

FINAL="$WORK/php-$VERSION-$ARCH"

./configure \
  --prefix="$FINAL" \
  --with-config-file-path="$FINAL/lib" \
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
# FIX LIBRARIES & DYLD
############################################
echo "🔧 Fixing DYLD Paths..."
BIN="$FINAL/bin/php"
LIBDIR="$FINAL/lib"
mkdir -p "$LIBDIR"

cp "$DEPS"/lib/*.dylib "$LIBDIR/" || true

for lib in libssl.3.dylib libcrypto.3.dylib libz.1.dylib libonig.5.dylib; do
  if [ -f "$LIBDIR/$lib" ]; then
    chmod 755 "$LIBDIR/$lib"
    install_name_tool -id "@rpath/$lib" "$LIBDIR/$lib"
    install_name_tool -change "$DEPS/lib/$lib" "@rpath/$lib" "$BIN"
  fi
done

if [ -f "$LIBDIR/libssl.3.dylib" ]; then
  install_name_tool -change "$DEPS/lib/libcrypto.3.dylib" "@rpath/libcrypto.3.dylib" "$LIBDIR/libssl.3.dylib"
fi

install_name_tool -add_rpath "@executable_path/../lib" "$BIN" || true

############################################
# 🚀 THE RELOCATABLE FIX
############################################
echo "📝 Writing Portable Config..."

# PHP-RUN WRAPPER
cat > "$FINAL/bin/php-run" <<'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
export PHPRC="$DIR/../lib"
export DYLD_LIBRARY_PATH="$DIR/../lib:$DYLD_LIBRARY_PATH"
exec "$DIR/php" -n -c "$DIR/../lib/php.ini" -d pcre.jit=0 "$@"
EOF
chmod +x "$FINAL/bin/php-run"

# PHP.INI (Placeholder paths)
# EXT_DIR ko hum setup.sh me replace karenge
cat > "$FINAL/lib/php.ini" <<EOF
pcre.jit=0
opcache.jit=0
zend_extension=opcache
opcache.enable=1
opcache.enable_cli=1
extension_dir = "REPLACE_ME_WITH_ACTUAL_DIR"
EOF

# SETUP.SH (The Intelligence)
cat > "$FINAL/setup.sh" <<'EOF'
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "🔐 Fixing Mac Security..."
xattr -rd com.apple.quarantine "$DIR" || true
chmod +x "$DIR/bin/php" "$DIR/bin/php-run" "$DIR/bin/pecl" "$DIR/bin/pear" || true

echo "🏠 Re-mapping Internal Paths..."
# Actual extension folder dhundna
ACTUAL_EXT_DIR=$(find "$DIR/lib/php/extensions" -name "no-debug-non-zts-*" -type d | head -n 1)
if [ -n "$ACTUAL_EXT_DIR" ]; then
  sed -i '' "s|extension_dir = \"REPLACE_ME_WITH_ACTUAL_DIR\"|extension_dir = \"$ACTUAL_EXT_DIR/\"|g" "$DIR/lib/php.ini"
fi

# PECL/PEAR hardcoded paths fix
sed -i '' "s|REPLACE_ME_WITH_DIR|$DIR|g" "$DIR/bin/pecl" "$DIR/bin/pear" 2>/dev/null || true

# Re-init PEAR/PECL to new local path
"$DIR/bin/php" -d pcre.jit=0 "$DIR/bin/pear" config-set php_bin "$DIR/bin/php" || true
"$DIR/bin/php" -d pcre.jit=0 "$DIR/bin/pear" config-set php_dir "$DIR/lib/php" || true

echo "🌐 Updating PECL Channels..."
"$DIR/bin/php-run" ./bin/pecl channel-update pecl.php.net || true
echo "✅ Setup Complete. Run: ./bin/php-run -v"
EOF
chmod +x "$FINAL/setup.sh"

# Fix PECL/PEAR wrapper paths during build
sed -i '' "s|$FINAL|REPLACE_ME_WITH_DIR|g" "$FINAL/bin/pecl" "$FINAL/bin/pear"

############################################
# PACKAGE
############################################
cd "$WORK"
zip -ry "$FINAL_OUT_DIR/php-$VERSION-$ARCH.zip" "php-$VERSION-$ARCH"
echo "✅ Build Finished."
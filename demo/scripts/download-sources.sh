#!/bin/bash
set -e

DEST_DIR="downloads"
PHP_DIR="$DEST_DIR/php"
DEPS_DIR="$DEST_DIR/deps"
PECL_DIR="$DEST_DIR/pecl"
DB_DIR="$DEST_DIR/db"
VERSION_FILE="versions/php-versions.txt"

mkdir -p "$PHP_DIR"
mkdir -p "$DEPS_DIR"
mkdir -p "$PECL_DIR"
mkdir -p "$DB_DIR"

############################################
# HELPER
############################################
download_file () {
  URL=$1
  TARGET=$2

  if [ -f "$TARGET" ]; then
    echo "✔ $(basename "$TARGET") exists"
    return
  fi

  echo "⬇ Downloading $(basename "$TARGET")"
  curl -L --fail -o "$TARGET" "$URL"
}

############################################
# CORE DEPENDENCIES
############################################
echo "=== Downloading Core Dependencies ==="

download_file \
  https://github.com/madler/zlib/releases/download/v1.3/zlib-1.3.tar.gz \
  "$DEPS_DIR/zlib-1.3.tar.gz"

download_file \
  https://www.openssl.org/source/openssl-3.2.1.tar.gz \
  "$DEPS_DIR/openssl-3.2.1.tar.gz"

download_file \
  https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz \
  "$DEPS_DIR/icu4c-74_2-src.tgz"

download_file \
  https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz \
  "$DEPS_DIR/onig-6.9.9.tar.gz"

download_file \
  https://libzip.org/download/libzip-1.10.1.tar.gz \
  "$DEPS_DIR/libzip-1.10.1.tar.gz"

############################################
# DATABASE CLIENTS (Future Ready)
############################################
echo
echo "=== Downloading Database Clients ==="

download_file \
  https://downloads.mariadb.com/Connectors/c/connector-c-3.3.8/mariadb-connector-c-3.3.8-src.tar.gz \
  "$DB_DIR/mariadb-connector-c-3.3.8-src.tar.gz"

download_file \
  https://ftp.postgresql.org/pub/source/v16.3/postgresql-16.3.tar.gz \
  "$DB_DIR/postgresql-16.3.tar.gz"

############################################
# PECL EXTENSIONS (Offline Install Ready)
############################################
echo
echo "=== Downloading PECL Extensions ==="

download_file \
  https://pecl.php.net/get/apcu-5.1.23.tgz \
  "$PECL_DIR/apcu-5.1.23.tgz"

download_file \
  https://pecl.php.net/get/redis-6.0.2.tgz \
  "$PECL_DIR/redis-6.0.2.tgz"

download_file \
  https://pecl.php.net/get/xdebug-3.3.2.tgz \
  "$PECL_DIR/xdebug-3.3.2.tgz"

############################################
# PHP VERSIONS
############################################
echo
echo "=== Downloading PHP Versions ==="

while IFS= read -r VERSION; do
  [[ -z "$VERSION" || "$VERSION" =~ ^# ]] && continue

  FILE="php-$VERSION.tar.gz"
  TARGET="$PHP_DIR/$FILE"

  if [ -f "$TARGET" ]; then
    echo "✔ $FILE exists"
    continue
  fi

  echo "⬇ Downloading PHP $VERSION"

  MAIN_URL="https://www.php.net/distributions/$FILE"
  ARCHIVE_URL="https://museum.php.net/php${VERSION%.*}/$FILE"

  if curl -L --fail -o "$TARGET" "$MAIN_URL"; then
    echo "✔ Main mirror"
  else
    echo "Main failed → Trying archive"
    curl -L --fail -o "$TARGET" "$ARCHIVE_URL"
  fi

  echo "--------------------------------"
done < "$VERSION_FILE"

echo
echo "==================================="
echo "✅ ALL DOWNLOADS COMPLETED"
echo "==================================="
#!/bin/bash
check() {
  echo -n "$1 : "
  curl -Is "$1" | head -n 1
}

check "https://zlib.net/zlib-1.3.tar.gz"
check "https://zlib.net/zlib-1.3.1.tar.gz"
check "https://zlib.net/zlib-1.3.2.tar.gz"
check "https://www.openssl.org/source/openssl-3.2.1.tar.gz"
check "https://www.openssl.org/source/old/3.2/openssl-3.2.1.tar.gz"
check "https://www.php.net/distributions/php-8.1.1.tar.gz"
check "https://www.php.net/distributions/php-8.1.1.tar.xz"
check "https://github.com/unicode-org/icu/releases/download/release-74-2/icu4c-74_2-src.tgz"
check "https://github.com/kkos/oniguruma/releases/download/v6.9.9/onig-6.9.9.tar.gz"

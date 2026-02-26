#!/bin/bash
set -e

PHP_DIR=$1
ROOT=$(pwd)
PECL_SRC=$ROOT/downloads/pecl

export PATH=$PHP_DIR/bin:$PATH

for FILE in $PECL_SRC/*.tgz; do
  tar -xf $FILE
  DIR=$(tar -tf $FILE | head -1 | cut -d"/" -f1)
  cd $DIR

  phpize
  ./configure --with-php-config=$PHP_DIR/bin/php-config
  make -j$(sysctl -n hw.ncpu)
  make install

  EXT=$(basename $FILE .tgz | cut -d- -f1)
  echo "extension=$EXT.so" >> $PHP_DIR/etc/php.ini

  cd ..
  rm -rf $DIR
done
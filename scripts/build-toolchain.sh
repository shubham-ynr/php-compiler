#!/bin/bash
set -e

ROOT=$(pwd)
SRC=$ROOT/downloads/toolchain
PREFIX=$ROOT/local-toolchain

mkdir -p $PREFIX
export PATH=$PREFIX/bin:$PATH

build() {
  FILE=$1
  NAME=$(basename $FILE .tar.gz)

  cd $ROOT
  rm -rf build-$NAME
  mkdir build-$NAME
  cd build-$NAME

  tar -xf $SRC/$FILE --strip-components=1
  ./configure --prefix=$PREFIX
  make -j$(sysctl -n hw.ncpu)
  make install
}

build m4-1.4.19.tar.gz
build autoconf-2.71.tar.gz
build automake-1.16.5.tar.gz
build libtool-2.4.7.tar.gz
build pkg-config-0.29.2.tar.gz
build bison-3.8.2.tar.gz
build re2c-3.1.tar.gz
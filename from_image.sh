#! /bin/bash -xeu


readonly tcdir=$1

./image2gpx.pl $tcdir/current.bin

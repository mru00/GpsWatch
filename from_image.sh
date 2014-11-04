#! /bin/bash -xeu

# Copyright (C) 2014 mru@sisyphus.teil.cc



readonly tcdir=$1

./image2gpx.pl $tcdir/current.bin

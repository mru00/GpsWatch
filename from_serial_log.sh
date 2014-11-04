#! /bin/bash -xeu

# Copyright (C) 2014 mru@sisyphus.teil.cc



readonly tcdir=$1

./parse.pl $tcdir/serial_log.txt
mv from_parse.bin $tcdir
mv l2.log $tcdir

./decode_memmap.pl $tcdir/from_parse.bin


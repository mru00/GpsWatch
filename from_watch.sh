#! /bin/bash -xu

# Copyright (C) 2014 mru@sisyphus.teil.cc


title=$1
desc=$(date +%Y%m%d_%H%M%S)_$title
mkdir $desc


rm last
mv current last
ln -s $desc current

./watch2image.pl

mv from_watch.bin $desc/current.bin
cp last/current.bin $desc/last.bin

./image2gpx.pl $desc/current.bin > $desc/decode.log

diff <(hexdump -C $desc/last.bin) <(hexdump -C $desc/current.bin) > $desc/diff.txt

echo "$title" > $desc/info.txt
$EDITOR $desc/info.txt





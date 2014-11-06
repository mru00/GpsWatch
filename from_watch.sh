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


./from_image $desc

echo "$title" > $desc/info.txt
$EDITOR $desc/info.txt





#! /bin/bash -xeu

desc=$(date +%Y%m%d_%H%M%S)_$*
mkdir $desc
./load_data.pl


mv from_watch.bin $desc/current.bin
cp last/current.bin $desc/last.bin

./decode_memmap.pl $desc/current.bin > $desc/decode.log

diff <(hexdump -C $desc/last.bin) <(hexdump -C $desc/current.bin) | tee $desc/diff.txt

$EDITOR $desc/info.txt

rm last
mv current last
ln -s $desc current



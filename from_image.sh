#! /bin/bash -xeu

# Copyright (C) 2014 mru@sisyphus.teil.cc



for tcdir in "$@"; do
  ./image2gpx.pl $tcdir/current.bin
  xmllint --schema gpx.xsd --noout $tcdir/current.bin.gpx
  xmllint --schema TrainingCenterDatabasev2.xsd --noout $tcdir/current.bin.tcx
done

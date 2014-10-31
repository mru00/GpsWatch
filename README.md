
activity names are always 10 bytes, \0 filled at the and


first block:
{
  0x0000 b checksum
  0x0001 b checksum_inv
  0x0003 b timezone

  0x001a b selected_profile
}

entry block 
{
  0x0000 b
  0x0001
  0x0002 lap count
  0x0003 ss  ... timestamp
  0x0004 mm
  0x0005 hh
  0x0006 dd
  0x0007 mm 
  0x0008 yy
  0x0009
  0x000a
  0x000b
  0x000c
  0x000d
  0x000e
  0x000f  selected profile
}


change 2:00 => 1:30

< 00000000  15 ea 00 1b 1a 10 53 03  1d 1b 4e 07 40 05 0a 00  |......S...N.@...|
---
> 00000000  16 e9 00 1c 1a 10 53 03  1d 1b 4e 07 40 05 0a 00  |......S...N.@...|



back to 1:

< 00000000  16 e9 00 1c 1a 10 53 03  1d 1b 4e 07 40 05 0a 00  |......S...N.@...|
---
> 00000000  14 eb 00 1a 1a 10 53 03  1d 1b 4e 07 40 05 0a 00  |......S...N.@...|



[0000-0004] timezone



http://download.runtastic.com/hardware/rungps1/manual/Runtastic_RUNGPS1_Manual_DE.pdf
Es wird der belegte Speicher der GPS-Uhr in % angezeigt. 1% des Speichers 
entspricht in etwa 480 in der GPS-Uhr gespeicherten Wegpunkten.

line 1+3
 (enum values unclear)
 0 00 Altitude
 1 01 Calories
 2 02 Distance
 3 03 Heading
 4 04 HR-Avg
 5 05 HR-Max
 6 06 HR-Min
 7 07 HR
 8 08 HRZ-Abv
 9 09 HRZ-Blw
10 0a HRZ-In
11 0b LapDist
12 0c LapNo
13 0d LapTime
14 0e Pace Avg
15 0f Pace Max
16 10 Pace
17 11 Speed Avg
18 12 Speed Max
19 13 Speed
20 14 TimeOfDay
21 15 Wkout Time

line 2
Distance
HR
LapDist
LatLong
PaceAvg
SpeedAvg
Speed
TimeOfDay
Wkout Time


screen config:
d1: 3
d2: 3
d4: 3
-> 9 entries
x { running, cycling, hiking, sailing, user } => 45 bytes

memmap:

settings: 0000-ffff

0060-0070: some version string
0600-0740: paths
0900-0940: activities

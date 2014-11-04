#! /usr/bin/perl
#
# Copyright (C) 2014 mru@sisyphus.teil.cc
#

use strict;
use warnings;

use GpsWatch;
use Device::SerialPort;
use Data::Dumper;



sub send_packet_l {
  my ($fh, $packet) = @_;
  $fh->write($packet);
}

my $bc = 0;
sub read_one {
  my ($port) = @_;
  my $count;
  my $b;
  ($count, $b) = $port->read(1);
  $bc ++;
  die "failed to read byte, count=$count, bc=$bc" unless $count == 1;
  my $r = unpack('H[2]',$b);
  return $r;
}

sub expect {
  my ($port, $expected) = @_;
  my $val = read_one($port);
  die sprintf("protocol error: 0x%x != 0x%x at b=$bc", $expected, $val) unless $val eq $expected;
  return $val;
}

sub receive_packet_l {
  my ($fh) = @_;
  my $packet;

  $packet .= expect($fh, 'a0');
  $packet .= expect($fh, 'a2');

  my $l1 = read_one($fh);
  my $l2 = read_one($fh);

  my $l = (hex $l1 << 8) + hex $l2;
  $packet .= $l1. $l2;

  $packet .= read_one($fh); # opcode
  for (my $i = 1; $i < $l; $i++) {
    $packet .= read_one($fh);
  }
  $packet .= read_one($fh); # checksum
  $packet .= read_one($fh); # checksum
  $packet .= expect($fh, 'b0');
  $packet .= expect($fh, 'b3');

  return pack('H*', $packet);
}


sub send_packet_h {
  my ($port, $hl) = @_;
  my $ll = GpsWatch::generate_tx($hl);
  send_packet_l($port, $ll);
  return GpsWatch::parse_w($ll);
}


sub receive_packet_h {
  my ($port) = @_;
  my $recv_l = GpsWatch::parse_r(receive_packet_l($port));
  return $recv_l;
}


my $port = Device::SerialPort->new ("/dev/ttyUSB0") or die "failed to open serial port: $!";
$port->baudrate(115200);
$port->parity('none');
$port->databits(8);
$port->stopbits(1);
$port->read_const_time(100);


my $commands = [
  { type => 'get_version' },
  { type => 'get_hw_id' },
];



# knowledge: memory wraps at 0x100000
# 0x2000 x 0x80 = 0x100000
# i.e., this is the full memory
my $num_trans = 0x2000;
my $size_trans = 128;
for (my $i = 0; $i < $num_trans; $i ++) {
  push (@$commands, { type => 'read_addr', addr=> $size_trans*$i, len => $size_trans, i => $i} );
}

printf( "reading %d / 0x%x bytes ( %d blocks of %d bytes )\n", $num_trans*$size_trans, $num_trans * $size_trans, $num_trans, $size_trans);

open(my $dump, ">", "from_watch.bin") or die "failed to open dump file: $!";
binmode ($dump, ':bytes');

foreach my $command ( @$commands) {
  my $send = send_packet_h($port,$command);
  my $recv = receive_packet_h($port);
  GpsWatch::conversation($send, $recv, $dump);
  print ".";
}





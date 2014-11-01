#! /usr/bin/perl
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

sub receive_packet_l {
  my ($fh) = @_;
  my $packet;

  my $count;
  my $current_byte;
  my $last_byte;
  while(1) {

    ($count, $current_byte) = $fh->read(1);

    $packet .= $current_byte;
    if (unpack('H*', $current_byte) eq 'b3' && unpack('H*', $last_byte) eq 'b0') {
      last;
    }
    $last_byte = $current_byte;
  }

  return $packet;
}


sub send_packet_h {
  my ($fh, $hl) = @_;
  my $ll = GpsWatch::generate_tx($hl);
  send_packet_l($fh, $ll);
  return GpsWatch::parse_w($ll);
}


sub receive_packet_h {
  my ($fh) = @_;
  my $recv_l = GpsWatch::parse_r(receive_packet_l($fh));
  return $recv_l;
}


my $port = Device::SerialPort->new ("/dev/ttyUSB0") or die "failed to open serial port: $!";
$port->baudrate(115200);
$port->parity('none');
$port->databits(8);
$port->stopbits(1);


my $commands = [
  { type => 'get_version' },
  { type => 'get_hw_id' },
];



my $num_trans = 0x5000;
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
  GpsWatch::conversation($send->{hl}, $recv->{hl}, $dump);
  print ".";
}





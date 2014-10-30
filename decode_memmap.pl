#! /usr/bin/perl
#
use strict;
use warnings;

use GpsWatch;
use Data::Dumper;


my $fn = $ARGV[0];

open(my $fh, '<', $fn) or die "failed to open file $!";
binmode($fh);
local $/;
my $data = <$fh>;
close($fh);


# 1000: 01 00 01 0C 14 00 1E 0A  0E 03 00 00 00 00 00 01
# 2000: 80 00 0E 0A 1E 00 14 0D  00 94 35 77 00 94 35 77
# 3000: 01 00 01 0E 18 00 1E 0A  0E 0A 00 00 00 00 00 01
# 4000: 80 00 0E 0A 1E 00 18 0F  00 94 35 77 00 94 35 77
# 5000: 02 00 01 0E 21 00 1E 0A  0E 10 00 00 00 00 00 01
# 6000: 80 00 0E 0A 1E 00 21 0F  00 94 35 77 00 94 35 77
# 7000: 02 00 02 1A 27 00 1E 0A  0E 10 00 00 00 00 00 01
# 8000: 80 00 0E 0A 1E 00 27 1B  00 94 35 77 00 94 35 77





sub parse_block_0 {
  my ($block) = @_;

  my $records = substr($block, 0x100, 32);
  my $last_block_num;
  my $wos = [];
  my $current_wo;
  for (my $i=0; ; $i++) {
    my $wo_entry = unpack('H*', substr($block, 0x100 + $i, 1));
    if ($wo_entry ne 'ff') {
      $current_wo = $wo_entry unless defined $current_wo;
    }
    elsif ($last_block_num ne 'ff') {
      push (@$wos, $current_wo);
      $current_wo = undef;
    }
    else {
      last;
    }
    $last_block_num = $wo_entry;
  }

  foreach my $wo (@$wos) {
    print "workout: ". Dumper($wo);
  }

  my $pathnames = substr($block, 0x600, 0x130);
  for(my $i = 0; $i < 10; $i ++) {
    print "pathname: ". substr($pathnames, $i*32, 32)."\n";
  }
}

sub parse_block_1 {
  my ($block) = @_;

  my $date = substr($block, 0, 16);

  my $date_str = unpack('H*', $date);
  my $date_arr = GpsWatch::hex_to_intarray($date_str);

  my $date_1 = sprintf("20%02d-%02d-%02d %02d:%02d",
    $date_arr->[8],
    $date_arr->[7],
    $date_arr->[6],
    $date_arr->[5],
    $date_arr->[4],
    $date_arr->[3],
    0, 0, 0, 0
  );

  print "$date_1\n";

}

my $block_0 = substr($data, 0, 0x1000);
my $block_1 = substr($data, 0x1000, 0x1000);


parse_block_0($block_0);
parse_block_1($block_1);

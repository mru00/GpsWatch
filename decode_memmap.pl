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
my $data_file = <$fh>;
close($fh);


# 1000: 01 00 01 0C 14 00 1E 0A  0E 03 00 00 00 00 00 01
# 2000: 80 00 0E 0A 1E 00 14 0D  00 94 35 77 00 94 35 77
# 3000: 01 00 01 0E 18 00 1E 0A  0E 0A 00 00 00 00 00 01
# 4000: 80 00 0E 0A 1E 00 18 0F  00 94 35 77 00 94 35 77
# 5000: 02 00 01 0E 21 00 1E 0A  0E 10 00 00 00 00 00 01
# 6000: 80 00 0E 0A 1E 00 21 0F  00 94 35 77 00 94 35 77
# 7000: 02 00 02 1A 27 00 1E 0A  0E 10 00 00 00 00 00 01
# 8000: 80 00 0E 0A 1E 00 27 1B  00 94 35 77 00 94 35 77



sub parse_entry_block {
  my ($data, $block_id) = @_;
  
  my $block_data = substr($data, $block_id * 0x1000);
  my $first_byte = hex unpack('H*', substr($block_data, 0, 1));

  my $result = {
    id => $block_id,
    fb => $first_byte,
    first_line => GpsWatch::hex_to_intarray(unpack('H*', substr($block_data, 0, 32)))
  };
  if ($first_byte == 0x80) {
    $result->{type} = 'end';
    return $result;
  }
  elsif ($first_byte == 0x01 || $first_byte == 0x02) {
    $result->{type} = 'start';
    return $result;
  }
  warn 'unknown block type: $first_byte';
}


sub parse_block_0 {
  my ($data) = @_;


  my $result = { };


  $result->{wos} = [];
  my $records = substr($data, 0x100, 32);
  my $last_block_num = 0xff;
  my $current_wo = [];
  push (@{$result->{wos}}, $current_wo);
  for (my $i=0; ; $i++) {
    my $wo_entry = hex unpack('H*', substr($data, 0x100 + $i, 1));
    if ($wo_entry != 0xff) {
      my $parsed = parse_entry_block($data, $wo_entry);
      push(@$current_wo, $parsed);
    }
    elsif ($last_block_num != 0xff) {
      $current_wo = [];
      push (@{$result->{wos}}, $current_wo);
    }
    else {
      last;
    }
    $last_block_num = $wo_entry;
  }

  $result->{pathnames} = [];
  my $pathnames = substr($data, 0x600, 0x130);
  for(my $i = 0; $i < 10; $i ++) {
    push(@{$result->{pathnames}}, substr($pathnames, $i*32, 32));
  }
  
  return $result;
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

my $parsed = parse_block_0($data_file);
print Dumper($parsed);

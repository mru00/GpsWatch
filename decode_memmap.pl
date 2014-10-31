#! /usr/bin/perl
#
use strict;
use warnings;

use GpsWatch;
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;




# 1000: 01 00 01 0C 14 00 1E 0A  0E 03 00 00 00 00 00 01
# 2000: 80 00 0E 0A 1E 00 14 0D  00 94 35 77 00 94 35 77
# 3000: 01 00 01 0E 18 00 1E 0A  0E 0A 00 00 00 00 00 01
# 4000: 80 00 0E 0A 1E 00 18 0F  00 94 35 77 00 94 35 77
# 5000: 02 00 01 0E 21 00 1E 0A  0E 10 00 00 00 00 00 01
# 6000: 80 00 0E 0A 1E 00 21 0F  00 94 35 77 00 94 35 77
# 7000: 02 00 02 1A 27 00 1E 0A  0E 10 00 00 00 00 00 01
# 8000: 80 00 0E 0A 1E 00 27 1B  00 94 35 77 00 94 35 77


sub get_byte_at {
  my ($data, $addr, $l) = @_;

  if ($l) {
    return GpsWatch::hex_to_intarray(unpack('H*', substr($data, $addr, $l)))
  }
  return hex unpack('H*', substr($data, $addr, 1));
}

sub parse_sample {
  my ($block_data, $start_addr) = @_;

  my $result = {
    type => $block_data->[$start_addr+0]
  };

  if ($result->{type} == 0x03) {

    $result->{length} = 8;

    $result->{timestamp} = sprintf("20%02d-%02d-%02d %02d:%02d:%02d",
      $block_data->[$start_addr+1],
      $block_data->[$start_addr+2],
      $block_data->[$start_addr+3],
      $block_data->[$start_addr+4],
      $block_data->[$start_addr+5],
      $block_data->[$start_addr+6],
    );

    $result->{hr} = $block_data->[$start_addr+7];
  }
  elsif ($result->{type} == 0x00) {

    warn "unknown sample type $result->{type}";
    # random number:
    $result->{length} = 0; 
  }
  else {
    die "unknown sample type $result->{type}";
    # random number:
    $result->{length} = 0; 
  }

  return $result;
}

sub parse_entry_block {
  my ($data, $block_id, $first_block) = @_;

  my $start_addr = 0x1000 * $block_id;
  my $block_data = get_byte_at($data, $start_addr, 0x1000);

  my $result = {
    profile => $block_data->[0x0f],
    start_addr => $start_addr,
    id => $block_id,
    fb => $block_data->[0],
    first_line => join(",", map { sprintf("%3d", $_) } @{get_byte_at($data, $start_addr, 2*32)} )
  };

  if (! $first_block) {

    $result->{numsamples} = $block_data->[0];
    $result->{lapcount} = $block_data->[2];
    $result->{laptimes} = [];

    $result->{date} = sprintf("20%02d-%02d-%02d %02d:%02d:%02d",
      $block_data->[3+5],
      $block_data->[3+4],
      $block_data->[3+3],
      $block_data->[3+2],
      $block_data->[3+1],
      $block_data->[3+0]
    );

    for (my $laps = 0; $laps < hex $result->{lapcount}; $laps ++) {
      push(@{$result->{laptimes}}, sprintf("%02d.%02d.%02d", 
          $block_data->[0x40+0x10*$laps + 1],
          $block_data->[0x40+0x10*$laps +2],
          sprintf ("%02x", $block_data->[0x40+0x10*$laps +3]), # bcd?
        ));
    }
  }
  else {
    my $numsamples = $first_block->{numsamples};
    $result->{samples} = [];
    my $block_offset = 25;
    for (my $i = 0; $i < $numsamples; $i++) {


      my $sample = parse_sample($block_data, $block_offset);
      $block_offset += $sample->{length};

      push(@{$result->{samples}}, $sample);
    }
  }



  return $result;
}



sub parse_block_alloc {
  my ($block_data) = @_;


  my $n = 0;
  while ( ($block_data->[0xe0 + $n/8] & ( 1<< ($n%8))) == 0) {
    $n++;
  };

  return $n;
}

sub parse_block_0 {
  my ($data) = @_;


  my $result = { };

  my $block_data = get_byte_at($data, 0, 0x1000);
  $result->{checksum} = $block_data->[0];
  $result->{checksum_inv} = $block_data->[1];
  $result->{timezone} = $block_data->[3];
  $result->{selected_profile} = $block_data->[0x10+10];

  $result->{nblocks} = parse_block_alloc($block_data);
  $result->{toc} = join(",", @{$block_data}[0x100..0x120] );

  warn 'checksum error' unless $result->{checksum} == ( 0xff & ~ $result->{checksum_inv}) ;


  if (length($data) > 0x1000) {
    $result->{wos} = [];
    my $current_wo = [];
    my $last_block_num = 0xff;
    my $first_block;
    push (@{$result->{wos}}, $current_wo);
    # xxx limit $i artifially
    for (my $i=0; $i < $result->{nblocks}-1 ; $i++) {
      my $wo_entry = $block_data->[0x100 + $i];
      if ($wo_entry != 0xff) {
        my $parsed = parse_entry_block($data, $wo_entry, $first_block);
        $first_block ||= $parsed;
        push(@$current_wo, $parsed);
      }
      elsif ($last_block_num != 0xff) {
        $current_wo = [];
        $first_block = 0;
        push (@{$result->{wos}}, $current_wo);
      }
      else {
        last;
      }
      $last_block_num = $wo_entry;
    }
  }
  else {
    $result->{wos} = "not included in dump";
  }

  $result->{pathnames} = [];
  my $pathnames = substr($data, 0x600, 0x130);
  for(my $i = 0; $i < 10; $i ++) {
    push(@{$result->{pathnames}}, substr($pathnames, $i*32, 32));
  }

  $result->{activities} = [];
  my $act_names = substr($data, 0x900, 0x032);
  for (my $i = 0; $i < 5; $i++) {
    push(@{$result->{activities}}, substr($act_names, $i*10, 10));
  }


  return $result;
}


foreach my $fn (@ARGV) {

  open(my $fh, '<', $fn) or die "failed to open file $!";
  binmode($fh);
  local $/;
  my $data_file = <$fh>;
  close($fh);
  print $fn . "\n";

  my $parsed = parse_block_0($data_file);
  $parsed->{input_file} = $fn;
  print Dumper($parsed);

  if (ref $parsed->{wos} eq "ARRAY") {
    #print Dumper($parsed->{nblocks}, $parsed->{224}, scalar @{$parsed->{wos}}, $parsed->{toc});
    foreach my $wo (@{$parsed->{wos}}) {
      print "\n";
      foreach my $entry (@$wo) {
        print( ">". $entry->{id} . "/". $entry->{first_line} . "\n");
      }
    }
  }
}

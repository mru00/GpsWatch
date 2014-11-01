#! /usr/bin/perl
#
use strict;
use warnings;

use GpsWatch;
use Data::Dumper;
use List::Util qw(sum);

$Data::Dumper::Sortkeys = 1;


sub hex_3_to_sint32 {
  my ($a,$b,$c) = @_;

  my $r = sprintf("%02x%02x%02x%02x", $a & 0x80 ? 255:0, $a, $b, $c);
  $r = hex $r;
  $r -= 0x100000000 if $r & 0x80000000;
  return $r;
}

sub format_arr {
  my ($arr) = @_;
  die "no arr specified" unless scalar @$arr;
  return join(',', map { die 'undef in format_arr'.Dumper(caller) unless defined $_; sprintf "%03d", $_} @{$arr});

}

sub parse_sample {
  my ($block_data, $start_addr, $id) = @_;

  my $result = {
    id => $id,
    type => $block_data->[$start_addr+0],
    addr => $start_addr,
  };

  my %lengths = (
    #plausible:
    0x00, 25,
    0x80, 25,
    0x01, 21,
    0x02, 8,
    0x03, 8,


    0xb1, 9,
    0x60, 7,
    0xdf, 7,
    0xd5, 5,
    0xf7, 5,
    0xcd, 5, 
    0x0d, 3,
    0x12, 19,
    0x34, 19,

    #unplausible
    0x42, 21,
    0x29, 19,
    0x39, 19,
  );

  die "result does not have a type specified @ $start_addr".Dumper(caller) unless defined $result->{type};
  $result->{length} = $lengths{$result->{type}} if defined $lengths{$result->{type}};

  if ($result->{type} == 0x00 || $result->{type} == 0x80) {
    $result->{timestamp} = sprintf("20%02d-%02d-%02d %02d:%02d:%02d",
      $block_data->[$start_addr+2],
      $block_data->[$start_addr+3],
      $block_data->[$start_addr+4],
      $block_data->[$start_addr+5],
      $block_data->[$start_addr+6],
      $block_data->[$start_addr+7],
    );
  }
  elsif ($result->{type} == 0x01) {
    $result->{timestamp} = sprintf("--:%02d:%02d",
      $block_data->[$start_addr+2],
      $block_data->[$start_addr+3],
    );
    $result->{d1} = hex_3_to_sint32($block_data->[$start_addr+7], $block_data->[$start_addr+6], $block_data->[$start_addr+5]);
    $result->{d2} = hex_3_to_sint32($block_data->[$start_addr+11], $block_data->[$start_addr+10], $block_data->[$start_addr+9]);
  }
  elsif ($result->{type} == 0x02) {
    $result->{timestamp} = sprintf("--:%02d:%02d",
      $block_data->[$start_addr+1],
      $block_data->[$start_addr+2],
    );
  }
  elsif ($result->{type} == 0x03) {
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
  elsif (defined $lengths{$result->{type}}) {
    $result->{length} = $lengths{$result->{type}};
  }
  else {
    die sprintf ("unknown sample type $result->{type} @ 0x%04x", $start_addr);
    # random number:
    $result->{length} = 0; 
  }

  die "no length for $result->{type} @ $start_addr" unless $result->{length};

  print ".";
  $result->{dump} = format_arr [ @{$block_data}[$start_addr .. $start_addr + $result->{length} -1] ];
  $result->{lookahead} = format_arr [ @{$block_data}[$start_addr + $result->{length} .. $start_addr + $result->{length} +0x10] ];
  return $result;
}

sub parse_entry_block {
  my ($data, $block_id, $first_block) = @_;

  my $start_addr = 0x1000 * $block_id;
  printf("parsing block %d from 0x%04x (img size: 0x%04x)\n", $block_id, $start_addr, scalar @$data);
  printf("nextblock: %d\n", $data->[$start_addr+1]) if $first_block == 0;;

  my $result = {
    is_first => !$first_block,
    profile => $data->[$start_addr + 0x0f],
    start_addr => $start_addr,
    id => $block_id,
    fb => $data->[$start_addr + 0],
    next_block => $data->[$start_addr + 1],
    #first_line => format_arr [@{$data}[$start_addr .. $start_addr+32]]
  };

  if (! $first_block) {

    $result->{numsamples} = $data->[$start_addr + 0];
    $result->{lapcount} = $data->[$start_addr + 2];
    $result->{laptimes} = [];

    printf("addr: $start_addr\n");
    $result->{date} = sprintf("20%02d-%02d-%02d %02d:%02d:%02d",
      $data->[$start_addr + 3+5],
      $data->[$start_addr + 3+4],
      $data->[$start_addr + 3+3],
      $data->[$start_addr + 3+2],
      $data->[$start_addr + 3+1],
      $data->[$start_addr + 3+0]
    );

    for (my $laps = 0; $laps < hex $result->{lapcount}; $laps ++) {
      my $questionable = 
          sprintf ("%02x", hex $data->[$start_addr + 0x40+0x10*$laps +3]); # bcd?
      push(@{$result->{laptimes}}, sprintf("%02d.%02d.%02d", 
          $data->[$start_addr + 0x40+0x10*$laps +1],
          $data->[$start_addr + 0x40+0x10*$laps +2], $questionable
        ));
    }
  }
  else {
    my $numsamples = $first_block->{numsamples};
    $result->{samples} = [];
    $result->{seen_sample_types} = {};
    my $block_offset = $start_addr;
    for (my $i = 0; $i <= $numsamples; $i++) {

      die "block_offset > length(data): $block_offset" if $block_offset > scalar @$data;
      my $sample = parse_sample($data, $block_offset, $i);
      $block_offset += $sample->{length};
      $result->{seen_sample_types}->{$sample->{type}} ++;

      push(@{$result->{samples}}, $sample);
    }
    printf("[%d]\n", scalar @{$result->{samples}});
    $result->{next_bytes} = format_arr [ @{$data}[$block_offset .. $block_offset+0x20] ];
  }



  return $result;
}



sub parse_block_alloc {
  my ($data) = @_;

  my $n = 0;
  while ( ($data->[0xe0 + $n/8] & ( 1<< ($n%8))) == 0) {
    $n++;
  };

  return $n;
}

sub parse_block_0 {
  my ($data) = @_;

  my $result = { };

  $result->{checksum} = $data->[0];
  $result->{checksum_inv} = $data->[1];
  $result->{timezone} = $data->[3];
  $result->{interval} = $data->[14];
  $result->{selected_profile} = $data->[0x10+10];

  $result->{nblocks} = parse_block_alloc($data);
  $result->{toc} = join(",", @{$data}[0x100..0x120] );
  $result->{allocf} = join(",", map {scalar reverse sprintf "%08b", $_ } @{$data}[0xe0..0xef] );
  $result->{allocb} = join(",", map {scalar reverse sprintf "%08b", $_ } @{$data}[0xf0..0xff] );

  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0xff]));
  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0xef]));
  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0x6f]));
  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0x5f]));
  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0x4f]));
  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0x3f]));
  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0x2f]));
  printf ("cs: $result->{checksum} vs. %d\n", 0xff & sum(@{$data}[0x02..0x1f]));
  warn 'checksum error' unless $result->{checksum} == ( 0xff & ~ $result->{checksum_inv}) ;

  if (@$data > 0x1000) {
    $result->{wos} = [];
    my $current_wo = [];
    my $last_block_num = 0xff;
    my $first_block = 0;


    my $next_block;
    for (my $i=0; scalar @{$result->{wos}} < $result->{nblocks}-1 ; $i++) {

      my $wo_entry = $data->[0x100 + $i];

      if ($wo_entry != 0xff) {
        if (@$current_wo == 0) {
          push (@{$result->{wos}}, $current_wo);
        }
        my $repl_block_id = $wo_entry;

        if (!$first_block) { $repl_block_id = $wo_entry; }
        else { $repl_block_id = $next_block || $wo_entry; }

        my $parsed = parse_entry_block($data, $repl_block_id, $first_block);
        if (! $first_block) {
          $first_block = $parsed;
          printf ("need to parse %d=0x%02x samples\n", $first_block->{numsamples}, $first_block->{numsamples});
        }

        printf ("leader: %03d/0x%02x - %02x\n", $data->[$parsed->{start_addr}], $data->[$parsed->{start_addr}], $data->[$parsed->{start_addr}+1]);
        push (@$current_wo, $parsed);
        #$next_block = $parsed->{next_block};
      }
      elsif ($last_block_num != 0xff) {
        $current_wo = [];
        $first_block = 0;
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
  for(my $i = 0; $i < 10; $i ++) {
    push(@{$result->{pathnames}}, pack('C*', @{$data}[0x600 + $i*32 .. 0x600 + ($i+1)*32-1]));
  }

  $result->{activities} = [];
  for (my $i = 0; $i < 5; $i++) {
    push(@{$result->{activities}}, pack('C*', @{$data}[0x900 + $i*10 .. 0x900 + ($i+1)*10-1]));
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
  my $data = GpsWatch::hex_to_intarray(unpack('H*',$data_file));

  my $parsed = parse_block_0($data);
  $parsed->{input_file} = $fn;
  print Dumper($parsed->{toc});
  print Dumper($parsed->{allocf});
  print Dumper($parsed->{allocb});
  print Dumper($parsed);


  if (ref $parsed->{wos} eq "ARRAY") {
    foreach my $wo (@{$parsed->{wos}}) {

      foreach my $entry (@$wo) {
        printf ( ">%02d\n", $entry->{id});
        if (!$entry->{is_first}) {
          foreach my $sample (@{$entry->{samples}}){
            printf ( " %02d %s\n", $sample->{id}, $sample->{dump});
          }
          printf ( "  f %s\n", $entry->{next_bytes});
        }
      }
    }
  }
  else {
    print $parsed->{wos} . "\n";
  }
}

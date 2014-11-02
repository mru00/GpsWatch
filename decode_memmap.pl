#! /usr/bin/perl
#
use strict;
use warnings;

use GpsWatch;
use Data::Dumper;
use List::Util qw(sum);

$Data::Dumper::Sortkeys = 1;


my $long_lat_scale = 10000000.0;

sub to_sint32 {
  my ($a) = @_;
  if (@$a == 4) {
    return unpack('l', pack ('L', $a->[0] + ($a->[1]<<8) + ($a->[2]<<16) +($a->[3]<<24)));
  }
  elsif (@$a ==2) {
    return unpack('s', pack ('S', $a->[0] + ($a->[1]<<8)));
  }
  elsif (@$a ==1) {
    return unpack('c', pack ('C', $a->[0] + ($a->[1]<<8)));
  }
  die "not implemented";
}

sub format_arr {
  my ($arr) = @_;
  die "no arr specified".Dumper(caller) unless defined $arr;
  return join(',', map { defined $_ ? sprintf( "%03d", $_ ): 'xxx'} @{$arr});

}

sub parse_sample {
  my ($data, $start_addr, $id) = @_;

  my $result = {
    id => $id,
    type => $data->[$start_addr],
    addr => $start_addr,
  };

  my %lengths = (
    #plausible:
    0x00, 25,
    0x80, 25,
    0x01, 21,
    0x02, 3,
    0x03, 8,
    0xff, 0
  );

  die "result does not have a type specified @ $start_addr".Dumper(caller)." " unless defined $result->{type};

  $result->{length} = $lengths{$result->{type}} if defined $lengths{$result->{type}};

  if ($result->{type} == 0x00 || $result->{type} == 0x80) {
    $result->{timestamp} = sprintf("20%02d-%02d-%02dT%02d:%02d:%02dZ",
      $data->[$start_addr+2],
      $data->[$start_addr+3],
      $data->[$start_addr+4],
      $data->[$start_addr+5],
      $data->[$start_addr+6],
      $data->[$start_addr+7],
    );

    my $d = $data;
    my $long_or_short_timestamp = 4;
    my $a = $long_or_short_timestamp + $start_addr;
    $result->{f1} = $d->[$start_addr+1];
    # then comes long timestamp for 000, short for 001
    $result->{lon} = to_sint32([@{$d}[$a+4 .. $a+7]]);
    $result->{lat} = to_sint32([@{$d}[$a+8 .. $a+11]]);
    $result->{ele} = to_sint32([@{$d}[$a+12 .. $a+13]]);
    $result->{f5} = $d->[$a+14];
    $result->{f6} = $d->[$a+15];
    $result->{f7} = $d->[$a+16];
    $result->{f8} = $d->[$a+17];
    $result->{f9} = $d->[$a+18];
    $result->{f10} = $d->[$a+19];
    $result->{f11} = $d->[$a+20];


  }
  elsif ($result->{type} == 0x01) {
    $result->{timestamp} = sprintf("%02d:%02d",
      $data->[$start_addr+2],
      $data->[$start_addr+3],
    );

    my $d = $data;
    my $long_or_short_timestamp = 0;
    my $a = $long_or_short_timestamp + $start_addr;
    $result->{f1} = $d->[$start_addr+1];
    # then comes long timestamp for 000, short for 001
    $result->{lon} = to_sint32([@{$d}[$a+4 .. $a+7]]);
    $result->{lat} = to_sint32([@{$d}[$a+8 .. $a+11]]);
    $result->{ele} = to_sint32([@{$d}[$a+12 .. $a+13]]);
    $result->{f5} = $d->[$a+14];
    $result->{f6} = $d->[$a+15];
    $result->{f7} = $d->[$a+16];
    $result->{f8} = $d->[$a+17];
    $result->{f9} = $d->[$a+18];
    $result->{f10} = $d->[$a+19];
    $result->{f11} = $d->[$a+20];
  }
  elsif ($result->{type} == 0x02) {
    $result->{timestamp} = sprintf("%02d:%02d",
      $data->[$start_addr+1],
      $data->[$start_addr+2],
    );
  }
  elsif ($result->{type} == 0x03) {
    $result->{timestamp} = sprintf("20%02d-%02d-%02d %02d:%02d:%02d",
      $data->[$start_addr+1],
      $data->[$start_addr+2],
      $data->[$start_addr+3],
      $data->[$start_addr+4],
      $data->[$start_addr+5],
      $data->[$start_addr+6],
    );

    $result->{hr} = $data->[$start_addr+7];
  }
  elsif ($result->{type} == 0xff) {
    # last entry.
  }
  else {
    die sprintf ("unknown sample type $result->{type} @ 0x%04x # %d", $start_addr, $id);
  }

  $result->{dump} = format_arr [ @{$data}[$start_addr .. $start_addr + $result->{length} -1] ];
  return $result;
}

sub parse_entry_block {
  my ($data, $block_id, $first_block) = @_;

  my $start_addr = 0x1000 * $block_id;
  #printf("\nparsing block %d from 0x%04x (img size: 0x%04x)\n", $block_id, $start_addr, scalar @$data);
  #printf("nextblock: %d\n", $data->[$start_addr+1]) if $first_block == 0;;

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

    # 6h45m56s
    # = 24356 sec
    # need to parse 23156=0x5a74 samples$
    #
    $result->{numsamples} = $data->[$start_addr + 0] + ($data->[$start_addr+1]<<8);
    $result->{lapcount} = $data->[$start_addr + 2];
    $result->{laptimes} = [];

    #printf("addr: 0x%04x\n", $start_addr);
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
      push(@{$result->{laptimes}}, sprintf("%02d:%02d:%02d.%02d", 
          $data->[$start_addr + 0x40+0x10*$laps +0],
          $data->[$start_addr + 0x40+0x10*$laps +1],
          $data->[$start_addr + 0x40+0x10*$laps +2], $questionable
        ));
    }
  }
  else {
    my $numsamples = $first_block->{numsamples};
    $result->{expected_num_samples} = $numsamples;
    $result->{samples} = [];
    $result->{seen_sample_types} = {};
    my $block_offset = $start_addr;
    for (my $i = 0; $i <= $numsamples; $i++) {

      die "block_offset > length(data): $block_offset" if $block_offset > scalar @$data;
      my $sample = parse_sample($data, $block_offset, $i);
      $block_offset += $sample->{length};
      $result->{seen_sample_types}->{$sample->{type}} ++;

      push(@{$result->{samples}}, $sample);

      if ($sample->{type} == 0xff) {
        $result->{incomplete_data} = 1;
        last;
      }
    }
    #printf("[%d]\n", scalar @{$result->{samples}});
    $result->{next_bytes} = format_arr [ @{$data}[$block_offset .. $block_offset+0x20] ];
  }



  return $result;
}



sub parse_block_alloc {
  my ($data) = @_;

  my $n = 0;
  while ( ($data->[0xe0 + $n/8] & ( 1<< ($n%8))) == 0) {
    $n++;
    die "failed to parse alloc" if $n > 1000;
  };

  return $n;
}

sub parse_block_0 {
  my ($data) = @_;

  my $result = { };

  die 'no data' unless defined $data && defined $data->[0];

  $result->{checksum} = $data->[0];
  $result->{checksum_inv} = $data->[1];
  die 'checksum error' unless $result->{checksum} == ( 0xff & ~ $result->{checksum_inv}) ;

  $result->{timezone} = $data->[3];
  $result->{interval} = $data->[14];
  $result->{selected_profile} = $data->[0x10+10];

  $result->{nblocks} = parse_block_alloc($data);
  $result->{toc} = join(",", @{$data}[0x100..0x120] );
  $result->{allocf} = join(",", map {scalar reverse sprintf "%08b", $_ } @{$data}[0xe0..0xef] );
  $result->{allocb} = join(",", map {scalar reverse sprintf "%08b", $_ } @{$data}[0xf0..0xff] );


  #print $result->{toc}."\n";


  if (@$data > 0x1000) {
    $result->{wos} = [];
    my $current_wo = [];
    my $last_block_num = 0xff;
    my $first_block = 0;


    for (my $i=0; scalar @{$result->{wos}} < $result->{nblocks}-1 ; $i++) {

      my $wo_entry = $data->[0x100 + $i];

      if ($wo_entry != 0xff) {

        if (@$current_wo == 0) { 

          push (@{$result->{wos}}, $current_wo);

          my $parsed = parse_entry_block($data, $wo_entry, 0);

          $first_block = $parsed;
          #printf ("need to parse %d=0x%02x samples\n", $parsed->{numsamples}, $parsed->{numsamples});
          #printf ("next block: %d 0x%02x\n", $parsed->{next_block}, $parsed->{next_block});
          #printf ("timestamp: %s\n", $parsed->{date});
          #printf (Dumper($parsed->{laptimes}));

          push (@$current_wo, $parsed);
        }
        elsif (@$current_wo == 1) {

          my $parsed = parse_entry_block($data, $wo_entry, $first_block);
          push (@$current_wo, $parsed);
        }
        else {
        }

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
    my $name = pack('C*', @{$data}[0x600 + $i*32 .. 0x600 + ($i+1)*32-1]);
    $name =~ s/\x00//g;
    push(@{$result->{pathnames}}, $name);
  }

  $result->{activities} = [];
  for (my $i = 0; $i < 5; $i++) {
    my $name = pack('C*', @{$data}[0x900 + $i*10 .. 0x900 + ($i+1)*10-1]);
    $name =~ s/\xff//g;
    push(@{$result->{activities}}, $name);
  }


  # global string table @ 0xf4000
  # global string table @ 0xf4000
  # global string table @ 0xf5000
  # global string table @ 0xf6000 DE
  # global string table @ 0xf7000
  return $result;
}


# braunau 48g15'30"N 13g2'6"E  351m  48.258333 13.035
# linz    48g18'N    14g17'E   266m  48.3 14.283333

sub parse_file {
  my ($data, $fn) = @_;


  my $parsed = parse_block_0($data);
  $parsed->{input_file} = $fn;
  #print Dumper($parsed->{toc});
  #print Dumper($parsed->{allocf});
  #print Dumper($parsed->{allocb});


  {
    open (my $fh_dump, '>', $fn.'.dump');
    print $fh_dump Dumper($parsed);
    close ($fh_dump);
  }
  
  {
    open (my $fh_decode, '>', $fn.'.decode');


    if (ref $parsed->{wos} eq "ARRAY") {
      my $wo_id = 0;
      foreach my $wo (@{$parsed->{wos}}) {

        foreach my $entry (@$wo) {
          printf ( $fh_decode ">%02d\n", $entry->{id});
          if (!$entry->{is_first}) {
            foreach my $sample (@{$entry->{samples}}){
              printf ( $fh_decode "i %02d %3.f/%3.f/%d %06x %4d %s [%s]\n", 
                $wo_id, 
                ($sample->{lat}|| 0) / $long_lat_scale, 
                ($sample->{lon}|| 0) / $long_lat_scale, 
                $sample->{ele} || 0, 
                $sample->{addr},
                $sample->{id}, 
                $sample->{dump},
                $sample->{type} == 0x00 ? 'fix' : ''
              );
            }
            printf ( $fh_decode "  f %s\n", $entry->{next_bytes});
          }
        }
        $wo_id ++;
      }
    }
    else {
      print $fh_decode $parsed->{wos} . "\n";
    }

    close($fh_decode);
  }

  return $parsed;
}

sub save_gpx {

  my ($parsed, $fn) = @_;


  open(my $fh, '>', $fn) or die "failed to open: $!";;

  print $fh <<EOF;
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" creator="crane gps watch" version="1.1">
EOF

  my $i = 0;
  foreach my $wo (@{$parsed->{wos}}) {
    $i ++;

    printf $fh " <trk><name>Track n.%d</name><trkseg>\n", $i;

    foreach my $entry (@$wo) {
      if (!$entry->{is_first}) {

        my $has_initial_fix = 0;
        my $lat = 0;
        my $lon = 0;
        my $ele = 0;
        my $timestamp = 0;

        foreach my $sample (@{$entry->{samples}}){
          my $write = 0;

          if ($sample->{type} == 0x00) {
            $has_initial_fix = 1;
            $lat = $sample->{lat};
            $lon = $sample->{lon};
            $ele = $sample->{ele};
            $timestamp = $sample->{timestamp};
            $write = 1;
          }
          elsif ($sample->{type} == 0x01) {
            $lat += $sample->{lat};
            $lon += $sample->{lon};
            $ele += $sample->{ele};
            $timestamp =~ s/..:..Z$/$sample->{timestamp}Z/;
            $write = 1 && $has_initial_fix;
          }

          if ($write) {
            printf($fh '   <trkpt lat="%f" lon="%f"><ele>%d</ele><time>%s</time></trkpt>'."\n",
              $lat/10000000.0, $lon/10000000.0, $ele, $timestamp);
          }


        }
      }
    }

    printf $fh " </trkseg></trk>\n";

  }

  print $fh '</gpx>';

  close($fh);

}

foreach my $fn (@ARGV) {

  open(my $fh, '<', $fn) or die "failed to open file $!";
  binmode($fh);
  local $/;
  my $data_file = <$fh>;
  close($fh);
  print STDERR $fn . "\n";
  my $data = GpsWatch::hex_to_intarray(unpack('H*',$data_file));
  eval {
    my $result = parse_file($data, $fn);
    save_gpx($result, $fn.".gpx");
    1;
  };
  if ($@) {
    warn "failed to parse file $fn: $@\n\n";
  };

}

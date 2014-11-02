#! /usr/bin/perl
#
use strict;
use warnings;

use GpsWatch;
use Data::Dumper;
use List::Util qw(sum);

# use XML::Writer; XXX
#

$Data::Dumper::Sortkeys = 1;



sub format_lon_lat {
  my ($val) = @_;
  my $long_lat_scale = 10000000.0;
  return $val / $long_lat_scale;
}

sub to_sint32 {
  if (@_ == 4) {
    return unpack('l', pack ('L', $_[0] + ($_[1]<<8) + ($_[2]<<16) +($_[3]<<24)));
  }
  elsif (@_ ==2) {
    return unpack('s', pack ('S', $_[0] + ($_[1]<<8)));
  }
  elsif (@_ ==1) {
    return unpack('c', pack ('C', $_[0]));
  }
  die "not implemented";
}

sub format_arr {
  return join(',', map { defined $_ ? sprintf( "%03d", $_ ): 'xxx'} @_);

}


sub format_gps_time {
  die "format_gps_time error: must give ref to 6-elem arr" unless (scalar @_) != 6;
  return sprintf("20%02d-%02d-%02dT%02d:%02d:%02dZ", @_);
}

sub format_mm_ss {
  die "format_gps_time error: must give ref to 2-elem arr" unless (scalar @_) != 2;
  return sprintf("%02d:%02d", @_);
}

sub parse_sample {
  my ($data, $addr, $id) = @_;

  my $result = {
    id => $id,
    type => $data->[$addr],
    addr => $addr,
  };

  my %lengths = (
    0x00, 25,
    0x80, 25,
    0x01, 21,
    0x02, 3,
    0x03, 8,
    0xff, 0
  );

  die "result does not have a type specified @ $addr".Dumper(caller)." " unless defined $result->{type};

  $result->{length} = $lengths{$result->{type}} if defined $lengths{$result->{type}};

  if ($result->{type} == 0x00 || $result->{type} == 0x80) {
    $result->{timestamp} = format_gps_time( @{$data}[$addr+2 .. $addr+8] );

    my $d = $data;
    my $long_or_short_timestamp = 4;
    my $a = $long_or_short_timestamp + $addr;
    $result->{f1} = $d->[$addr+1];
    # then comes long timestamp for 000, short for 001
    $result->{lon} = to_sint32(@{$d}[$a+4 .. $a+7]);
    $result->{lat} = to_sint32(@{$d}[$a+8 .. $a+11]);
    $result->{ele} = to_sint32(@{$d}[$a+12 .. $a+13]);
    $result->{f5} = $d->[$a+14];
    $result->{f6} = $d->[$a+15];
    $result->{f7} = $d->[$a+16];
    $result->{f8} = $d->[$a+17];
    $result->{f9} = $d->[$a+18];
    $result->{f10} = $d->[$a+19];
    $result->{hr} = $d->[$a+20];


  }
  elsif ($result->{type} == 0x01) {
    $result->{timestamp} = format_mm_ss( @{$data}[$addr+2..$addr+4] );

    my $d = $data;
    my $long_or_short_timestamp = 0;
    my $a = $long_or_short_timestamp + $addr;
    $result->{f1} = $d->[$addr+1];
    # then comes long timestamp for 000, short for 001
    $result->{lon} = to_sint32(@{$d}[$a+4 .. $a+7]);
    $result->{lat} = to_sint32(@{$d}[$a+8 .. $a+11]);
    $result->{ele} = to_sint32(@{$d}[$a+12 .. $a+13]);
    $result->{f5} = $d->[$a+14];
    $result->{f6} = $d->[$a+15];
    $result->{f7} = $d->[$a+16];
    $result->{f8} = $d->[$a+17];
    $result->{f9} = $d->[$a+18];
    $result->{f10} = $d->[$a+19];
    $result->{hr} = $d->[$a+20];
  }
  elsif ($result->{type} == 0x02) {
    $result->{timestamp} = format_mm_ss( @{$data}[$addr+1..$addr+3] );
  }
  elsif ($result->{type} == 0x03) {
    $result->{timestamp} = format_gps_time( @{$data}[$addr+1 .. $addr+7] );

    $result->{hr} = $data->[$addr+7];
  }
  elsif ($result->{type} == 0xff) {
    # last entry.
    # XXX here, something is still wrong.
    # :
  }
  else {
    die sprintf ("unknown sample type $result->{type} @ 0x%04x # %d", $addr, $id);
  }

  $result->{dump} = format_arr  @{$data}[$addr .. $addr + $result->{length} -1];
  return $result;
}

sub parse_leader_block {

  my ($data, $block_id, $first_block) = @_;
  my $addr = 0x1000 * $block_id;

  my $result = {
    is_first => !$first_block,
    profile => $data->[$addr + 0x0f],
    addr => $addr,
    id => $block_id,
  };

  # 6h45m56s
  # = 24356 sec
  # need to parse 23156=0x5a74 samples$
  #
  $result->{numsamples} = $data->[$addr + 0] + ($data->[$addr+1]<<8);
  $result->{lapcount} = $data->[$addr + 2];
  $result->{laptimes} = [];
  $result->{laprecords} = [];

  $result->{date} = format_gps_time( reverse @{$data}[$addr+3 .. $addr+3+6] );

  for (my $laps = 0; $laps < hex $result->{lapcount}; $laps ++) {

    my $lap_start = $addr + 0x40+0x10*$laps;
    my $fractions = sprintf ("%02x", hex $data->[$lap_start +3]); # bcd?

    push(@{$result->{laptimes}}, sprintf("%02d:%02d:%02d.%02d", 
        $data->[$lap_start +0],
        $data->[$lap_start +1],
        $data->[$lap_start +2], $fractions
      ));
    push (@{$result->{laprecords}},  format_arr @{$data}[$lap_start .. $lap_start + 15]);
  }

  return $result;
}

sub parse_sample_block {
  my ($data, $block_id, $leader) = @_;

  my $addr = 0x1000 * $block_id;

  my $result = {
    profile => $data->[$addr + 0x0f],
    addr => $addr,
    id => $block_id,
  };

    my $numsamples = $leader->{numsamples};
    $result->{expected_num_samples} = $numsamples;
    $result->{samples} = [];
    $result->{seen_sample_types} = {};
    my $block_offset = $addr;
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
    $result->{next_bytes} = format_arr @{$data}[$block_offset .. $block_offset+0x20];

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
  $result->{toc} = join(",", @{$data}[0x100..0x13f] );
  $result->{allocf} = join(",", map {scalar reverse sprintf "%08b", $_ } @{$data}[0xe0..0xef] );
  $result->{allocb} = join(",", map {scalar reverse sprintf "%08b", $_ } @{$data}[0xf0..0xff] );


  if (@$data > 0x1000) {

    $result->{wos} = [];
    my $last_block_num = 0xff;

    my $leader = 1;

    for (my $i=0; scalar @{$result->{wos}} < $result->{nblocks}-1 ; $i++) {

      my $wo_entry = $data->[0x100 + $i];

      if ($wo_entry != 0xff) {

        if ($leader == 1) { 

          my $parsed = parse_leader_block($data, $wo_entry, 0);

          $parsed->{samples} = parse_sample_block($data, $wo_entry+1, $parsed);

          push (@{$result->{wos}}, $parsed);
          $leader = 0;
        }

      }
      elsif ($last_block_num != 0xff) {
        $leader = 1;
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

        foreach my $entry ($wo->{samples}) {
          printf ( $fh_decode ">%02d\n", $entry->{id});
          if (!$entry->{is_first}) {
            foreach my $sample (@{$entry->{samples}}){

              printf ( $fh_decode "i %02d %3.f/%3.f/%d/%d %06x %4d %s [%s]\n", 
                $wo_id, 
                $sample->{lat}|| 0, 
                $sample->{lon}|| 0, 
                $sample->{ele} || 0, 
                $sample->{hr} || 0,
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

  printf( $fh qq|
    <metadata>
    <name>%s</name>
    <author>%s</author>
    <copyright author="%s">
    <year>2014</year>
    <license>beer license</license>
    </copyright>
    </metadata>
    |,
    "GPS Track from Crane GPS Watch",
    'mru@sisyphus.teil.cc',
    'mru@sisyphus.teil.cc');

  my $i = 0;
  if (ref $parsed->{wos} eq "ARRAY") {
    foreach my $wo (@{$parsed->{wos}}) {
      $i ++;

      printf $fh " <trk><name>Track n.%d</name><trkseg>\n", $i;

      my $entry = $wo->{samples};
      if (!$entry->{is_first}) {

        my $has_initial_fix = 0;
        my $lat = 0;
        my $lon = 0;
        my $ele = 0;
        my $timestamp = 0;

        foreach my $sample (@{$entry->{samples}}){
          my $write = 0;

          if ($sample->{type} == 0x00 || $sample->{type} == 0x80) {
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
          elsif ($sample->{type} == 0x02) {
            $timestamp =~ s/..:..Z$/$sample->{timestamp}Z/;
            $write = 1 && $has_initial_fix;
          }
          elsif ($sample->{type} == 0x03) {
            $timestamp = $sample->{timestamp};
          }

          if ($write) {
            printf($fh '   <trkpt lat="%f" lon="%f"><ele>%d</ele><time>%s</time></trkpt>'."\n",
              format_lon_lat($lat), 
              format_lon_lat($lon), 
              $ele, 
              $timestamp);
          }
          else {
            printf($fh '   <trkpt><time>%s</time></trkpt>'."\n",
              $timestamp);
          }
        }
      }
    }

    printf $fh " </trkseg></trk>\n";

  }
  else {
    print $fh "<!-- no data included in memdump -->\n";
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

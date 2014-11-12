#! /usr/bin/perl
#
# Copyright (C) 2014 mru@sisyphus.teil.cc
#
use strict;
use warnings;

use GpsWatch;
use Data::Dumper;
use List::Util qw(sum);

use XML::Writer;
#

$Data::Dumper::Sortkeys = 1;



sub format_lon_lat {
  my ($val) = @_;
  return $val / 10000000.0;
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

sub to_uint {
  if (@_ == 4) {
    return $_[0] + ($_[1]<<8) + ($_[2]<<16) +($_[3]<<24);
  }
  elsif (@_ ==2) {
    return $_[0] + ($_[1]<<8);
  }
  elsif (@_ ==1) {
    return $_[0];
  }
  die "not implemented : ".@_.Dumper(caller);
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

  if ($result->{type} == 0x00 || $result->{type} == 0x01 || $result->{type} == 0x80) {

    my $a;
    my $d = $data;
    $result->{fix_quality_hunch} = $d->[$addr+1];
    if ($result->{type} == 0x01) {
      $result->{timestamp} = format_mm_ss( @{$data}[$addr+2..$addr+4] );
      $a = $addr;
    }
    else {
      $result->{timestamp} = format_gps_time( @{$data}[$addr+2 .. $addr+8] );
      $a = $addr + 4;
    }
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
    addr => $addr,
    id => $block_id,
  };

  # 6h45m56s
  # = 24356 sec
  # need to parse 23156=0x5a74 samples$
  #
  # nn nn ll ss  ss ss ss ss   -   ss ww ww ww  ?? ?? ?? pp
  $result->{numsamples} = to_uint( @{$data}[$addr..$addr+1]);
  $result->{lapcount} = $data->[$addr + 2];

  $result->{start_time} = format_gps_time( reverse @{$data}[$addr+2 .. $addr+8] );
  $result->{total_workout_time} = sprintf("%02d:%02d:%02d", reverse @{$data}[$addr+8 .. $addr+11] );
  $result->{profile} = $data->[$addr + 15];

  # km km km km  av av ma ma   -   ?? ?? ?? ??  ?? ?? ?? ??
  $result->{total_km} = sprintf("%.3f", to_uint( @{$data}[$addr+16 .. $addr+19]) / 10000.0);
  $result->{avg_speed} = sprintf("%.1f", to_uint( @{$data}[$addr+20 .. $addr+21] ) / 10.0);
  $result->{max_speed} = sprintf("%.1f", to_uint ( @{$data}[$addr+22 .. $addr+23]) / 10.0);

  # cc cc ?? ??  ?? ?? ?? ??   -   ?? ?? ?? ??  ?? ?? ?? ??
  $result->{calories} = sprintf("%.1f", to_uint( @{$data}[$addr+32 .. $addr+33]) / 100.0);
  $result->{dump} = format_arr(@{$data}[$addr..$addr+128]);


  # missing:
  # time hr inzone  hh:mm:ss
  # hr above  hh mm ss
  # hr below  hh mm ss
  # hr min
  # hr max 
  # hr avg

  $result->{laps} = [];
  $result->{laprecords} = [];
  for (my $laps = 0; $laps < $result->{lapcount}; $laps ++) {

    # tt tt tt tt  ?? ?? ?? ??   -  km km km km  sp sp ??
    my $lap_start = $addr + 0x40 + 0x10*$laps;
    my $lap = {};

    # missing: lap avg hr
    # accum time
    # accum distance
    # accum speed
    $lap->{laptime} = sprintf("%02d:%02d:%02d.%02x", @{$data}[$lap_start .. $lap_start+3] );
    $lap->{km} = sprintf("%.3f", to_uint( @{$data}[$lap_start + 8 .. $lap_start+11]) / 10000.0);
    $lap->{avg_speed} = sprintf("%.1f", to_uint( @{$data}[$lap_start+12 .. $lap_start+13] ) / 10.0);

    push(@{$result->{laps}}, $lap);
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

  $result->{profiles} = [];
  for (my $i = 0; $i < 5; $i++) {
    my $name = pack('C*', @{$data}[0x900 + $i*10 .. 0x900 + ($i+1)*10-1]);
    $name =~ s/\xff|\x00//g;
    push(@{$result->{profiles}}, $name);
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


sub save_tcx {
#http://www8.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd

  my ($parsed, $fn) = @_;

  my $output = IO::File->new(">$fn");
  my $ns_def = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2";
  my $xml = XML::Writer->new(
    OUTPUT => $output,
    NAMESPACES => 1,
    DATA_MODE => 1,
    DATA_INDENT => ' ',
    FORCED_NS_DECLS => [ $ns_def ],
    PREFIX_MAP => {
      $ns_def => '',
      "http://www.w3.org/2001/XMLSchema-instance" => 'xsi'
    }
  );

  $xml->xmlDecl();
  $xml->startTag('TrainingCenterDatabase');


  $xml->startTag('Activities');


  {
    my $i = 0;
    if (ref $parsed->{wos} eq "ARRAY") {
      foreach my $wo (@{$parsed->{wos}}) {
        $i ++;

        $xml->startTag('Activity', Sport=> 'Other');
        $xml->dataElement(Id => $wo->{start_time});
        $xml->startTag('Lap', StartTime => $wo->{start_time});
        $xml->dataElement(TotalTimeSeconds => 0);
        $xml->dataElement(DistanceMeters => 0);
        $xml->dataElement(Calories => int($wo->{calories}));
        $xml->dataElement(Intensity => 'Active');
        $xml->dataElement(TriggerMethod => 'Manual');

        $xml->startTag('Track');


        my $entry = $wo->{samples};
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
            elsif ($sample->{type} == 0x02) {
              $timestamp =~ s/..:..Z$/$sample->{timestamp}Z/;
            }
            elsif ($sample->{type} == 0x03 || $sample->{type} == 0x80) {
              $timestamp = $sample->{timestamp};
            }

            $xml->startTag('Trackpoint');
            $xml->dataElement(Time => $timestamp);

            if ($write) {
              $xml->startTag('Position');
              $xml->dataElement(LatitudeDegrees=>format_lon_lat($lat));
              $xml->dataElement(LongitudeDegrees=>format_lon_lat($lon));
              $xml->endTag('Position');

              $xml->dataElement(AltitudeMeters=>$ele);

            }

            if (defined $sample->{hr} && $sample->{hr} != 0) {
              $xml->startTag('HeartRateBpm');
              $xml->dataElement(Value => $sample->{hr});
              $xml->endTag('HeartRateBpm');
            }

            $xml->endTag('Trackpoint');
          }
        }
        $xml->endTag('Track');


        $xml->dataElement(Notes => 'created track');

        $xml->endTag('Lap');


        $xml->dataElement(Notes => 'created lap');
        $xml->endTag('Activity');




      }
    }
    else {
      $xml->comment("no data included in memdump");
    }
  }


  $xml->endTag('Activities');


  $xml->endTag('TrainingCenterDatabase');
  $xml->end();
  $output->close();

}

sub save_gpx {

  # gpx files do not allow to add trackpoints without position.
  # this means: it is impossible to create proper gpx's with the hometrainer:
  # heartrate without gps

  my ($parsed, $fn) = @_;

  my $output = IO::File->new(">$fn");
  my $ns_def = "http://www.topografix.com/GPX/1/1";
  my $ns_gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1";
  my $xml = XML::Writer->new(
    OUTPUT => $output,
    NAMESPACES => 1,
    DATA_MODE => 1,
    DATA_INDENT => ' ',
    FORCED_NS_DECLS => [ $ns_gpxtpx, $ns_def ],
    PREFIX_MAP => {
      $ns_def => '',
      $ns_gpxtpx => 'gpxtpx',
      "http://www.garmin.com/xmlschemas/GpxExtensions/v3" => 'gpxx',
      "http://www.w3.org/2001/XMLSchema-instance" => 'xsi'
    }
  );

  $xml->xmlDecl();
  $xml->startTag('gpx', creator => "gpswatch", version => "1.1");

  $xml->startTag('metadata');
    $xml->dataElement(name => "GPS Track from Crane GPS Watch");
    $xml->startTag('author');
    $xml->dataElement('email'=>'', id => 'mru', domain => 'sisyphus.teil.cc');
    $xml->endTag('author');

    $xml->startTag('copyright', author => 'mru@sisyphus.teil.cc');
      $xml->dataElement(year => 2014);
      $xml->dataElement(license => 'beer license');
    $xml->endTag('copyright');
  $xml->endTag('metadata');



  {
    my $i = 0;
    if (ref $parsed->{wos} eq "ARRAY") {
      foreach my $wo (@{$parsed->{wos}}) {
        $i ++;

        $xml->startTag('trk');
        $xml->dataElement(name => $wo->{start_time});
        $xml->dataElement(cmt=> '');
        $xml->dataElement(desc => $parsed->{profiles}->[$wo->{profile}]);
        $xml->dataElement(src => 'gps watch');
        $xml->dataElement(number => $i);
        $xml->dataElement(type => $parsed->{profiles}->[$wo->{profile}]);
        $xml->startTag('trkseg');


        my $entry = $wo->{samples};
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
            elsif ($sample->{type} == 0x02) {
              $timestamp =~ s/..:..Z$/$sample->{timestamp}Z/;
            }
            elsif ($sample->{type} == 0x03 || $sample->{type} == 0x80) {
              $timestamp = $sample->{timestamp};
            }


            if ($write) {
              $xml->startTag('trkpt', lat => format_lon_lat($lat), lon => format_lon_lat($lon));
              $xml->dataElement(ele=>$ele);
              $xml->dataElement(time => $timestamp);
            }
            else {
              # this is wrong (according to the xsd):
              $xml->startTag('trkpt', lat => 0, lon => 0);
              $xml->dataElement(fix=>"none");
            }

            if (defined $sample->{hr} && $sample->{hr} != 0) {
              $xml->startTag('extensions');
              $xml->startTag([$ns_gpxtpx=>'TrackPointExtension']);
              $xml->dataElement([$ns_gpxtpx=>'hr'], $sample->{hr});
              $xml->endTag();
              $xml->endTag('extensions');

            }
            $xml->endTag('trkpt');
          }
        }
        $xml->endTag('trkseg');
        $xml->endTag('trk');
      }
    }
    else {
      $xml->comment("no data included in memdump");
    }
  }


  $xml->endTag('gpx');
  $xml->end();
  $output->close();

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
    save_tcx($result, $fn.".tcx");
    1;
  };
  if ($@) {
    warn "failed to parse file $fn: $@\n\n";
  };

}

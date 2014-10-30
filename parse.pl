#! /usr/bin/perl
#

use strict;
use warnings;

use GpsWatch;
use List::Util qw(sum);
use Data::Dumper;


sub parse_line {
  my ($line) = @_;

  $_ = $line;
  if (/^.?$/) {
    return {
      type => "noop"
    };
  }
  if (/\[(..\/..\/.... ..:..:..)\] - Open port (\w*) (\(C:\\Program Files\\GPS Master 2.0.14\\GPS Master.exe)\)/) {
    return {
      time => $1,
      port => $2,
      process => $3,
      type => "open"
    };
  }
  if (/\[(..\/..\/.... ..:..:..)\] - Close port (\w*)/) {
    return {
      type => "close", 
      port => $2,
      time => $1
    };
  }
  if (/\[(..\/..\/.... ..:..:..)\] Read data/) {
    return {
      type => "read",
      time => $1,
      data => []
    };
  }
  if (/\[(..\/..\/.... ..:..:..)\] Written data/) {

    return {
      type => "write",
      time => $1,
      data => []
    };
  }

  if (/    (.. .. .. .. .. .. .. .. .. .. .. .. .. .. .. ..)   ................/) {
    return {
      type => "data",
      data => $1
    };
  }

  die "failed to parse line: '$line' (line $.)";
}


sub parse_file {

  my @entries;
  my $current_entry;
  while(<>) {
    chomp;
    s/\r//;

    my $entry = parse_line($_);
    die "failed to parse line: '$_'" unless $entry;
    if ($entry->{type} eq "open") {
    }
    elsif ($entry->{type} eq "close") {
    }
    elsif ($entry->{type} eq "read" or $entry->{type} eq "write") {
      $current_entry = $entry;
      push (@entries, $current_entry);
    }
    elsif ($entry->{type} eq "data") {
      push (@{$current_entry->{data}}, $entry->{data});
    }
    elsif ($entry->{type} eq "noop") {
      #no-op
    }
    else {
      die "unknown entry type $entry->{type}";
    }
  }
  return \@entries;
}

our $rw;

sub foreach_entry {
  my ($entries, $filter, $callback) = @_;
  foreach my $entry (@$entries) {
    if ($entry->{type} =~ m/$filter/) {
      local $_ = $entry;
      local $rw = $entry->{type};
      $rw =~ s/(.).*/$1/;
      $callback->($entry);
    }
  }
}

sub postproc_data {
  my ($entries) = @_;
  foreach_entry($entries, "read|write", sub {
      my $data;
      $data = join(" ", map { $_ } @{$_->{data}});
      $data =~ s/ //g;
      $_->{data} = pack ('H*', $data);
    });
}


sub join_streams {
  my ($entries) = @_;

  my $tx_data = "";
  my $rx_data = "";

  open(my $tx_fh, ">", \$tx_data);
  open(my $rx_fh, ">", \$rx_data);
  binmode($tx_fh, ":bytes");
  binmode($rx_fh, ":bytes");

  my %stream_selector = ( "r" => $rx_fh, "w" => $tx_fh);

  foreach_entry($entries, "read|write", sub {
      my $stream = $stream_selector{$rw};
      print $stream $_->{data};
    });

  close($rx_fh);
  close($tx_fh);
  return ($tx_data, $rx_data);
}


sub tokenize_stream {
  my ($stream, $from) = @_;
  my $data; 

  my $current_byte;
  my $last_byte;
  my $i;

  for (my $i = $from; ; $i ++) {
    return if $i >= length($stream);
    #die "failed to detect end marker" if $i >= length($stream);

    $current_byte = unpack('H[2]', substr($stream, $i, 1));
    return $i if $current_byte eq 'b3' && $last_byte eq 'b0';

    $last_byte = $current_byte;
  }
}



sub partition_stream {
  my ($stream) = @_;

  my $parts = [];
  my $from = 0;
  my $to;
  while ( defined ($to = tokenize_stream($stream, $from))) {

    push (@$parts, substr($stream, $from, 1+$to-$from));
    $from = $to + 1;
  }
  $parts;
}



my $entries = parse_file();

postproc_data($entries);

(my $tx_stream, my $rx_stream) = join_streams($entries);

my $tx_part = partition_stream($tx_stream);
my $rx_part = partition_stream($rx_stream);

$tx_part->[0] = GpsWatch::generate_tx( { type => "get_version" });
$tx_part->[1] = GpsWatch::generate_tx( { type => "get_hw_id" });
$tx_part->[2] = GpsWatch::generate_tx( { type => "read_addr", addr=> 0, len=>128 });
$tx_part->[3] = GpsWatch::generate_tx( { type => "read_addr", addr=> 128, len=>128 });
$tx_part->[4] = GpsWatch::generate_tx( { type => "read_addr", addr=> 256, len=>128 });



my @process_later_tx;
my @process_later_rx;

open(my $memmap_file, ">", "from_parse.bin");
binmode ($memmap_file, ':bytes');

for (my $i = 0; $i < @$tx_part; $i ++) {
  my $tx_data = GpsWatch::parse_w($tx_part->[$i]);
  my $rx_data = GpsWatch::parse_r($rx_part->[$i]);

  GpsWatch::conversation($tx_data->{hl}, $rx_data->{hl}, $memmap_file);
}




# perl
#
#

package GpsWatch;


use List::Util qw(sum);
use Data::Dumper;

my $leader = 'a0a200';
my $trailer = 'b0b3';

my $OP_TX_UNKN_1 = '012c';  # hw id?
my $OP_TX_GET_VER = '0110';
my $OP_TX_READ_ADDR = '0512';
my $OP_TX_UNKN_2 = '0124';  # clear?
my $OP_TX_UNKN_3 = '0414';  # ???
my $OP_TX_UNKN_4 = '8516';

my $OP_RX_UNKN_1 = '0a2d';
my $OP_RX_GET_VER = '0811';
my $OP_RX_READ_ADDR = '8113';
my $OP_RX_UNKN_2 = '0125';
my $OP_RX_UNKN_3 = '0115';
my $OP_RX_UNKN_4 = '0117';

sub hex_to_intarray {
	my ($data) = @_;
	my @fields = ( $data =~ m/../g );

	return [ map { hex } @fields ];
}

sub parse_packet {
	my ($packet) = @_;

	my $as_hex = unpack('H*', $packet);

	my $payload;
	my $opcode_h;
	my $opcode_l;
	my $checksum;
	my $data;
	unless ($as_hex =~ /^$leader((..)(..)(.*)(....))$trailer$/) {
		die "fail head/trail error in '$as_hex'";
	}
	$data = $1;
	$opcode_h = $2;
	$opcode_l = $3;
	$payload = $4;
	$checksum = $5;

	my $checksummable = hex_to_intarray($opcode_l.$payload);
	my $cs_synth = sprintf("%04x", 0x7fff & sum(@$checksummable));

  warn "checksum error: received: $checksum != calculated: $cs_synth" unless $checksum eq $cs_synth;

	#printf ("o=%s%s l=%04d p=%s c=%s\n", $opcode_h, $opcode_l, length($payload)/2, $payload, $checksum);

	return {
		data=> $data,
		opcode => $opcode_h.$opcode_l,
		opcode_h => $opcode_h,
		opcode_l => $opcode_l,
		payload => $payload,
		payload_l => (length($payload)/2),
		checksum => $checksum
	}
}


my %rx_opcodes;
my %tx_opcodes;
my %payload_size;
my %addr_seen;

sub parse_w {
	my ($packet) = @_;
	my $data = parse_packet($packet);
	$tx_opcodes{$data->{opcode}} ++;
	$payload_size{$data->{payload_l}} ++;
	#printf ("w o=%s l=%-4d p=%s\n", $data->{opcode}, $data->{payload_l}, $data->{payload});

	$data->{direction} = "tx";
	if ($data->{opcode} eq $OP_TX_READ_ADDR) {
		$data->{payload} =~ /(..)(..)(..)(..)/;
		$data->{hl} = {
			type => "read_addr",
			seg => $1,
			addr => $3.$2.$1,
			len => $4
		};

		$addr_seen{$data->{hl}->{addr}} ++;
	}
	elsif ($data->{opcode} eq $OP_TX_GET_VER) {
		$data->{hl} = {
			type => "get_version"
		};
	}
	elsif ($data->{opcode} eq $OP_TX_UNKN_1) {
		$data->{hl} = {
			type => "get_hw_id"
		};
	}
  elsif ($data->{opcode} eq $OP_TX_UNKN_2) {
    $data->{hl} = {
      type => "clear"
    };
  }
  elsif ($data->{opcode} eq $OP_TX_UNKN_3) {
    $data->{hl} = {
      type => "unkn3"
    };
  }
  elsif ($data->{opcode} eq $OP_TX_UNKN_4) {
    $data->{hl} = {
      type => "unkn4"
    };
  }
	else {
		die "unknown tx opcode $data->{opcode}";
	}
	return $data;
}

sub parse_r {
	my ($packet) = @_;
	my $data = parse_packet($packet);
	$rx_opcodes{$data->{opcode}} ++;
	$payload_size{$data->{payload_l}} ++;
	#printf ("r o=%s l=%-4d p=%s\n", $data->{opcode}, $data->{payload_l}, $data->{payload});

	$data->{direction} = "rx";
	if ($data->{opcode} eq $OP_RX_GET_VER) {
		$data->{hl} = {
			type => "get_version",
			version => pack('H*', $data->{payload})
		}
	}
	elsif ($data->{opcode} eq $OP_RX_UNKN_1) {
		$data->{hl} = {
			type => "get_hw_id",
			hw_id => $data->{payload}
		}
	}
	elsif ($data->{opcode} eq $OP_RX_READ_ADDR) {
		$data->{hl} = {
			type => "read_addr",
			data => $data->{payload}
		}
	}
  elsif ($data->{opcode} eq $OP_RX_UNKN_2) {
    $data->{hl} = { type => "unkn2" };
  }
  elsif ($data->{opcode} eq $OP_RX_UNKN_3) {
    $data->{hl} = { type => "unkn3" };
  }
  elsif ($data->{opcode} eq $OP_RX_UNKN_4) {
    $data->{hl} = { type => "unkn4" };
  }
	else {
		die "unknown rx opcode $data->{opcode}";
	}
	return $data;

}

sub conversation {
	my ($request, $response, $dump) = @_;

	my $rx = $response;
	my $tx = $request;

  # tx-clear -> rx-read
  #die "conversation error, $tx->{type} != $rx->{type}" unless $rx->{type} eq $tx->{type};

	if ($tx->{type} eq "get_version") {
		print "get_version => $rx->{version}\n";
	}
	elsif ($tx->{type} eq "get_hw_id") {
		print "get_hw_id => $rx->{hw_id}\n";
	}
	elsif ($tx->{type} eq "read_addr") {
    my $len_actual = length($rx->{data});
    #print "read $tx->{len} from $tx->{addr}, received $len_actual => memmap\n";
		seek($dump, hex $tx->{addr}, 0);
		syswrite($dump, pack('H*', $rx->{data}));
	}
  elsif($tx->{type} eq 'clear' || $tx->{type} =~ /unkn/) {
    print "unknown => $rx->{data}\n";
  }
  else {
    die "unknown conversation, $tx->{type} != $rx->{type}";
  }

}


sub generate_packet {
  my ($opcode, $payload) = @_;

	my $opcode_l;

  $opcode =~ /(..)(..)/;
  $opcode_l = $2;

	my $checksummable = hex_to_intarray($opcode_l.$payload);
	my $checksum = sprintf("%04x", sum(@$checksummable));

  return pack('H*', $leader.$opcode.$payload.$checksum.$trailer);
}

sub generate_tx {
  my ($hl) = @_;
  my $payload;
  if ($hl->{type} eq "get_version") {
    return generate_packet($OP_TX_GET_VER, '');
  }

  if ($hl->{type} eq "get_hw_id") {
    return generate_packet($OP_TX_UNKN_1, '');
  }

  if ($hl->{type} eq "read_addr") {
    my $addr = sprintf("%06x", $hl->{addr});
    my $len = sprintf("%02x", $hl->{len});
    $addr =~ s/(..)(..)(..)/$3$2$1/;
    return generate_packet($OP_TX_READ_ADDR, $addr.$len);
  }

  die "failed to generate packet for $hl->{type}";
}

1;


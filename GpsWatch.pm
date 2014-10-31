# perl
#
#

package GpsWatch;

use warnings;
use strict;

use List::Util qw(sum);
use Data::Dumper;

my $leader = 'a0a2';
my $trailer = 'b0b3';

my $OP_UNKN_1 = '2c';  # hw id?
my $OP_GET_VER = '10';
my $OP_READ_ADDR = '12';
my $OP_UNKN_2 = '24';  # clear?
my $OP_UNKN_3 = '14';  # ???
my $OP_UNKN_4 = '16';


sub hex_to_intarray {
	my ($data) = @_;
	my @fields = ( $data =~ m/../g );

	return [ map { hex } @fields ];
}

sub parse_packet {
	my ($packet) = @_;

	my $as_hex = unpack('H*', $packet);

	my $payload;
	my $opcode;
	my $checksum;
	my $length;
	my $data;
	unless ($as_hex =~ /^$leader((....)(..)((?:..)*)(....))$trailer$/) {
		die "fail head/trail error in '$as_hex'";
	}
	$data = $1;
	$length = hex $2;
	$opcode = $3;
	$payload = $4;
	$checksum = $5;

	my $checksummable = hex_to_intarray($opcode.$payload);
	my $cs_synth = sprintf("%04x", 0x7fff & sum(@$checksummable));

	my $len_recv = length($opcode.$payload)/2;
	warn "length mismatch: received: $len_recv expected: $length" unless $length == $len_recv;
  warn "checksum error: received: $checksum != calculated: $cs_synth" unless $checksum eq $cs_synth;

	#printf ("o=%s%s l=%04d p=%s c=%s\n", $opcode_h, $opcode_l, length($payload)/2, $payload, $checksum);

	return {
		data=> $data,
		opcode => $opcode,
		length => $length,
		payload => $payload,
		payload_l => $length,
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
	if ($data->{opcode} eq $OP_READ_ADDR) {
		$data->{payload} =~ /(..)(..)(..)(..)/;
		$data->{hl} = {
			type => "read_addr",
			seg => $1,
			addr => $3.$2.$1,
			len => $4
		};

		$addr_seen{$data->{hl}->{addr}} ++;
	}
	elsif ($data->{opcode} eq $OP_GET_VER) {
		$data->{hl} = {
			type => "get_version"
		};
	}
	elsif ($data->{opcode} eq $OP_UNKN_1) {
		$data->{hl} = {
			type => "get_hw_id"
		};
	}
	else {
		warn "unknown tx opcode $data->{opcode}";
    $data->{hl} = { type => "unknown_$data->{opcode}" };
	}
	return $data;
}


sub make_rx_opcode {
	my ($op) = @_;
	$op = hex $op;
	return sprintf("%02x", $op +1);
}
sub make_tx_opcode {
	my ($op) = @_;
	$op = hex $op;
	return sprintf("%02x", $op -1 );
}

sub parse_r {
	my ($packet) = @_;
	my $data = parse_packet($packet);
	$rx_opcodes{$data->{opcode}} ++;
	$payload_size{$data->{payload_l}} ++;
	#printf ("r o=%s l=%-4d p=%s\n", $data->{opcode}, $data->{payload_l}, $data->{payload});

	$data->{direction} = "rx";
	if ($data->{opcode} eq make_rx_opcode($OP_GET_VER)) {
		$data->{hl} = {
			type => "get_version",
			version => pack('H*', $data->{payload})
		}
	}
	elsif ($data->{opcode} eq make_rx_opcode($OP_UNKN_1)) {
		$data->{hl} = {
			type => "get_hw_id",
			hw_id => $data->{payload}
		}
	}
	elsif ($data->{opcode} eq make_rx_opcode($OP_READ_ADDR)) {
		$data->{hl} = {
			type => "read_addr",
			data => $data->{payload}
		}
	}
  else {
		warn "unknown rx opcode $data->{opcode}";
    my $opcode_tx = make_tx_opcode($data->{opcode});
    $data->{hl} = { type => "unknown_$opcode_tx" };
  }
	return $data;

}

sub conversation {
	my ($request, $response, $dump) = @_;

	my $rx = $response;
	my $tx = $request;

  # tx-clear -> rx-read
  if ($rx->{type} ne $tx->{type}) {
    warn "conversation error, $tx->{type} != $rx->{type}";
    return;
  }

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
  elsif($tx->{type} =~ /unkn/) {
    print "unknown: $tx->{type}\n";
  }
  else {
    die "unknown conversation, $tx->{type} != $rx->{type}";
  }

}


sub generate_packet {
  my ($opcode, $payload) = @_;

	my $length = sprintf("%04x", length($opcode.$payload)/2);
	my $checksummable = hex_to_intarray($opcode.$payload);
	my $checksum = sprintf("%04x", sum(@$checksummable));

  return pack('H*', $leader.$length.$opcode.$payload.$checksum.$trailer);
}

sub generate_tx {
  my ($hl) = @_;
  my $payload;
  if ($hl->{type} eq "get_version") {
    return generate_packet($OP_GET_VER, '');
  }

  if ($hl->{type} eq "get_hw_id") {
    return generate_packet($OP_UNKN_1, '');
  }

  if ($hl->{type} eq "read_addr") {
    my $addr = sprintf("%06x", $hl->{addr});
    my $len = sprintf("%02x", $hl->{len});
    $addr =~ s/(..)(..)(..)/$3$2$1/;
    return generate_packet($OP_READ_ADDR, $addr.$len);
  }

  die "failed to generate packet for $hl->{type}";
}

1;


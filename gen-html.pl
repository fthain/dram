#!/usr/bin/perl

# Copyright (c) 2007-2015, 2022 Finn Thain

use 5.008;
use strict;
use warnings;

my %chips;
# Manufacturer, Part, Structure, Type
open(IN, '<', 'chips.tsv') or die 'open failed';
while (<IN>) {
	chomp;
	my @F = split /\t/;
	die unless scalar(@F) == 4;
	$chips{$F[1]} = { 'mfr' => $F[0], 'org' => $F[2], 'type' => $F[3] };
	my $bits = $F[2];
	$bits =~ s/M/*1048576/g;
	$bits =~ s/K/*1024/g;
	$bits =~ s/x/*/g;
	$bits =~ s/[^0-9*]//g;
	$chips{$F[1]}{bits} = eval $bits;
}
close IN;

my %keywords;
grep {
	s/ .*//;
	s/-.*//;
	s/^([A-Z]+)([0-9]+)([A-Z]+)$/$1$2/;
	s/^([A-Z]+)([0-9]+)([A-Z][A-Z]+)([0-9]+)$/$1$2/;
	s/^([A-Z]+)([0-9]+)([A-Z])([0-9]+).*/$1$2$3$4/;
	$keywords{$_} = 0;
} keys %chips;
my $keywords = join(' ', sort keys %keywords);

print qq(<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html><head>
<title>DRAM</title>
<meta name="keywords" content="$keywords">
</head><body>
);

print "<h1>Chips</h1><p><table>\n";
print qq(<tr bgcolor="#000000"><td><font color="#FFFFFF">Manufacturer</font></td>
<td><font color="#FFFFFF">Part Code</font></td>
<td><font color="#FFFFFF">Structure</font></td>
<td><font color="#FFFFFF">DRAM Type</font></td></tr>\n);
my $j = 0;
grep {
	my $bgcolor = $j++ % 2 ? '#D4D4D4' : '#FFFFFF';
	print qq(<tr bgcolor="$bgcolor"><td>$chips{$_}{mfr}</td>
<td><a name="$_">$_</a></td>
<td>$chips{$_}{org}</td>
<td>$chips{$_}{type}</td></tr>\n)
} sort keys %chips;
print qq(</table></p>\n);

sub mB_to_bits {
	my $mB = shift;
	$mB =~ s/[^0-9]//g;
	return 0 unless $mB;
	return 8 * 1024 * 1024 * $mB;
}

sub render_device_html {
	my $d = shift;
	if (defined $chips{$d}) {
	} else {
		print STDERR "$d\n";
		$d
	}
}

sub strip_parens {
	my $r = shift;
	$r =~ s/^([^\(]*)\(.*\)([^\)]*)$/$1$2/;
	return $r
}

my @modules;
# Qty, Connector, Part, Chips per module, MBytes, Origin, Notes
open(IN, '<', 'modules.tsv') or die 'open failed';
READ: while (<IN>) {
	chomp;
	my @F = split /\t/, $_, -1;
	die join(':', @F) unless scalar(@F) == 7;
	my $module_bits = 0;
	my @FF = split /,/, $F[3];
	my @devices;
	my $module_type;
	for my $ff (@FF) {
		my %device;
		my @mfr = ();
		my @markings = split ' ', $ff;
		my $n = shift @markings;
		$n = undef unless $n eq (''.int($n));
		shift(@markings) eq 'x' or die;
		HERE: $_ = shift @markings;
		if (defined $_) {
			if (/[^A-Za-z]/) {
				unshift @markings, $_;
			} else {
				push @mfr, $_;
				goto HERE
			}
		}
		my $chip = "@markings";
		my $chip_html = join '&nbsp;', @markings;
		if (defined $n) {
			$device{count} = $n;
			$module_bits += $n * $chips{$chip}{bits} if defined $chips{$chip};
		} else {
			$device{count} = '?'
		}
		if (defined($chips{$chip})) {
			if (defined($module_type) and $chips{$chip}{type} ne $module_type) {
				$module_type = "mismatched";
				warn "mismatched type @FF"
			} else {
				$module_type = $chips{$chip}{type}
			}
			$device{html} = qq($device{count}&nbsp;x&nbsp;<a href="#$chip">$chip_html</a>)
		} else {
			$device{html} = $ff;
			$device{html} =~ s/ /&nbsp;/g;
		}
		push @devices, \%device;
	}
	push @modules, { 'qty' => $F[0],
	                 'connector' => $F[1],
	                 'part' => $F[2],
	                 'chips' => join(', ', map { $_->{html} }
	                                       sort { $b->{count} <=> $a->{count} }
	                                       @devices),
	                 'type' => $module_type,
	                 'MB_tested' => $F[4],
	                 'origin' => strip_parens( $F[5] ),
	                 'notes' => $F[6] };

	my $b = mB_to_bits $F[4];
	warn "size incorrect? $b vs $module_bits = @FF\n"
		if $b and $module_bits and
		   $b != $module_bits and
		   $b != $module_bits / 9 * 8 # parity kludge
}
close IN;

sub connector_cmp {
	my @a = split ' ', shift;
	my @b = split ' ', shift;
	if ($a[0] + 0 eq "$a[0]" and $b[0] + 0 eq "$b[0]") {
		my $result = $a[0] <=> $b[0];
		return $result if $result;
		shift @a;
		shift @b;
	}
	return $a[0] cmp $b[0]
}

print qq(<br><h1>Modules</h1><p><table>\n);
my @order = (0..$#modules);
@order = sort { connector_cmp($modules[$a]{connector}, $modules[$b]{connector}) }
               sort { $modules[$a]{type}      cmp $modules[$b]{type} }
               sort { $modules[$a]{MB_tested} <=> $modules[$b]{MB_tested} } @order;
print qq(<tr bgcolor="#000000">);
print qq(<td><font color="#FFFFFF">Module Type</font></td>);
print qq(<td><font color="#FFFFFF">Part Code</font></td>);
print qq(<td><font color="#FFFFFF">Chips</font></td>);
print qq(<td><font color="#FFFFFF">RAM Type</font></td>);
print qq(<td><font color="#FFFFFF">Size Tested (MB)</font></td>);
print qq(<td><font color="#FFFFFF">Origin</font></td>);
print qq(<td><font color="#FFFFFF">Notes</font></td>);
print qq(</tr>\n);
for $j (0..$#order) {
	my $bgcolor = $j % 2 ? "#D4D4D4" : "#FFFFFF";
	my $i = $order[$j];
	print qq(<tr bgcolor="$bgcolor">);
	print qq(<td>$modules[$i]{connector}</td>);
	print qq(<td>$modules[$i]{part}</td>);
	print qq(<td>$modules[$i]{chips}</td>);
	print qq(<td>$modules[$i]{type}</td>);
	print qq(<td>$modules[$i]{MB_tested}</td>);
	print qq(<td>$modules[$i]{origin}</td>);
	print qq(<td>$modules[$i]{notes}</td>);
	print qq(</tr>\n);
}
print qq(</table></p>\n);

print <<END;
<br>
<i>
<p>Page generated from data kept at <a href="https://github.com/fthain/dram/tree/master">https://github.com/fthain/dram/tree/master</a></p>
<p>If you have corrections or additions please send a pull request
or open a new issue.</p>
</i>
</body></html>
END

package Locale::Maketext::Simple;

use strict;
use warnings;

our $VERSION = '0.01';

sub import {
    my ($class, @args) = @_;
    my %opts = @args % 2 == 0 ? @args : ();
    my $caller = caller;
    my $export = $opts{Export} || 'loc';

    no strict 'refs';
    *{"${caller}::${export}"} = \&loc;
}

sub _plural {
    my ($value, $single, $plural) = @_;
    return (defined $value && $value == 1) ? $single : $plural;
}

sub loc {
    my ($msg, @args) = @_;
    return '' if !defined $msg;
    my $text = $msg;

    $text =~ s/\[\s*_(\d+)\s*\]/
        defined $args[$1 - 1] ? $args[$1 - 1] : ''
    /gex;

    $text =~ s/\[\s*\*\s*,\s*_(\d+)\s*,\s*([^\],]+)\s*,\s*([^\]]+)\]/
        _plural($args[$1 - 1], $2, $3)
    /gex;

    return $text;
}

1;

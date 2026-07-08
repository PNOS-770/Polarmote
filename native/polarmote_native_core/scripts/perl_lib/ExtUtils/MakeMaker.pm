package ExtUtils::MakeMaker;

use strict;
use warnings;

our $VERSION = '0.01';

package MM;

sub maybe_command {
    my ($class, $path) = @_;
    return undef if !defined $path || $path eq '';

    if (_is_executable_file($path)) {
        return $path;
    }

    for my $suffix (qw(.exe .cmd .bat .com)) {
        my $candidate = $path . $suffix;
        if (_is_executable_file($candidate)) {
            return $candidate;
        }
    }

    return undef;
}

sub _is_executable_file {
    my ($path) = @_;
    return 0 if !defined $path || $path eq '';
    return 0 if !-f $path;
    return 1 if -x $path;
    return 1;
}

1;

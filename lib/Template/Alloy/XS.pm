package CGI::Ex::Template::XS;

=head1 NAME

CGI::Ex::Template::XS - Attempted XS version of CGI::Ex::Template

=cut

use strict;
use warnings;
use XSLoader;
use base qw(CGI::Ex::Template);

our $VERSION = '0.01';
XSLoader::load('CGI::Ex::Template::XS', $VERSION);

1;

__END__


=head1 SYNOPSIS

    use CGI::Ex::Template::XS;

    # see the CGI::Ex::Template documentation

=head1 DESCRIPTION

This is an attempt to get XS speeds for the CGI::Ex::Template functionality.

=head1 AUTHOR

Paul Seamons, E<lt>paul@seamons.comE<gt>

=cut

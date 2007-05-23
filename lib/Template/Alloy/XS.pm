package CGI::Ex::Template::XS;

=head1 NAME

CGI::Ex::Template::XS - XS version of key parts of CGI::Ex::Template

=cut

use strict;
use warnings;
use XSLoader;
use v5.8.0;
use CGI::Ex::Template 2.14;
use base qw(CGI::Ex::Template);

our $VERSION = '0.03';
XSLoader::load('CGI::Ex::Template::XS', $VERSION);

### method used for debugging XS
sub __dump_any {
    my ($self, $data) = @_;
    require CGI::Ex::Dump;
    CGI::Ex::Dump::debug($data);
}

### this is here because I don't know how to call
### builtins from XS - anybody know how?
sub __lc { lc $_[0] }

1;

__END__


=head1 SYNOPSIS

    use CGI::Ex::Template::XS;

    my $obj = CGI::Ex::Template::XS->new;

    # see the CGI::Ex::Template documentation

=head1 DESCRIPTION

This module allows key portions of the CGI::Ex::Template module to run in XS.

All of the methods of CGI::Ex::Template are available.  All configuration
parameters, and all output should be the same.  You should be able
to use this package directly in place of CGI::Ex::Template.

=head1 BUGS/TODO

=over 4

=item Memory leak

The use of FILTER aliases causes a memory leak in a cached environment.
The following is an example of a construct that can cause the leak.

  [% n=1; n FILTER echo=repeat(2); n FILTER echo %]

Anybody with input or insight into fixing the code is welcome to submit
a patch :).

=item undefined_any

The XS version doesn't call undefined_any when play_expr finds an
undefined value.  It needs to.

=back

=head1 AUTHOR

Paul Seamons, E<lt>paul@seamons.comE<gt>

=head1 LICENSE

This module may be distributed under the same terms as Perl itself.

=cut

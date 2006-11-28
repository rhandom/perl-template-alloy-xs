# -*- Mode: Perl; -*-

use Test::More tests => 8;

use_ok('CGI::Ex::Template::XS');

{
package Foo;
@Foo::ISA = qw(CGI::Ex::Template::XS);

sub foobar { my $s = 234; return $s  }
}



my $c = CGI::Ex::Template::XS->new({foo => 1});
ok($c, "Got an object");

my $i = eval { $c->test_xs };
ok($i, "XS is on the way ($i)");

my $f = Foo->new;
ok($f, "Got subclassed object");
ok($f->foobar, "Has new method");
$i = eval { $f->test_xs };
ok($i, "XS is on the way ($i)");


my $s = "[% a %]";
my $o;
eval { $c->process(\$s, {a => "A"}, \$o) };
my $err = $@;
ok(! $err, "Print shouldn't have error ($err)");
ok($o eq "A", "Got the right output ($o)");


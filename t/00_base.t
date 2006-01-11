# -*- Mode: Perl; -*-

use vars qw($module $is_tt);
BEGIN {
    $module = 'CGI::Ex::Template';
    #$module = 'Template';
    $is_tt = $module eq 'Template';
};

use strict;
use Test::More tests => 222 - ($is_tt ? 18 : 0);
use Data::Dumper qw(Dumper);


use_ok($module);

sub process_ok { # process the value
    my $str  = shift;
    my $test = shift;
    my $args = shift;
    my $out  = '';
    my $obj = $module->new(ABSOLUTE => 1);
    $obj->process(\$str, $args, \$out);
    my $ok = $out eq $test;
    ok($ok, "\"$str\" => \"$out\"" . ($ok ? '' : " - should've been \"$test\""));
    my $line = (caller)[2];
    warn "#   process_ok called at line $line.\n" if ! $ok;
    print Dumper $obj->parse_tree(\$str) if ! $ok && $obj->can('parse_tree');
    exit if ! $ok;
}

{
    package OBJ;
    sub new { bless {}, __PACKAGE__ }
    sub seven { 7 }
    sub many { return 1, 2, 3 }
    sub echo { my $self = shift; $_[0] }
}
my $obj = OBJ->new;

###----------------------------------------------------------------###
### variable GETting

process_ok("[% foo %]" => "");
process_ok("[% foo %]" => "7",       {foo => 7});
process_ok("[% foo %][% foo %][% foo %]" => "777", {foo => 7});
process_ok("[% foo() %]" => "7",     {foo => 7});
process_ok("[% foo.bar %]" => "");
process_ok("[% foo.bar %]" => "",    {foo => {}});
process_ok("[% foo.bar %]" => "7",   {foo => {bar => 7}});
process_ok("[% foo().bar %]" => "7", {foo => {bar => 7}});
process_ok("[% foo.0 %]" => "7",     {foo => [7, 2, 3]});
process_ok("[% foo.10 %]" => "",     {foo => [7, 2, 3]});
process_ok("[% foo %]" => 7,         {foo => sub { 7 }});
process_ok("[% foo(7) %]" => 7,      {foo => sub { $_[0] }});
process_ok("[% foo.length %]" => 1,  {foo => sub { 7 }});
process_ok("[% foo.0 %]" => 7,       {foo => sub { return 7, 2, 3 }});
process_ok("[% foo(bar) %]" => 7,    {foo => sub { $_[0] }, bar => 7});
process_ok("[% foo.seven %]" => 7,   {foo => $obj});
process_ok("[% foo.seven() %]" => 7, {foo => $obj});
process_ok("[% foo.seven.length %]" => 1, {foo => $obj});
process_ok("[% foo.echo(7) %]" => 7, {foo => $obj});
process_ok("[% foo.many.0 %]" => 1,  {foo => $obj});
process_ok("[% foo.many.10 %]" => '',{foo => $obj});
process_ok("[% foo.nomethod %]" => '',{foo => $obj});
process_ok("[% foo.nomethod.0 %]" => '',{foo => $obj});

process_ok("[% GET foo %]" => "");
process_ok("[% GET foo %]" => "7",     {foo => 7});
process_ok("[% GET foo.bar %]" => "");
process_ok("[% GET foo.bar %]" => "",  {foo => {}});
process_ok("[% GET foo.bar %]" => "7", {foo => {bar => 7}});
process_ok("[% GET foo.0 %]" => "7",   {foo => [7, 2, 3]});
process_ok("[% GET foo %]" => 7,       {foo => sub { 7 }});
process_ok("[% GET foo(7) %]" => 7,    {foo => sub { $_[0] }});

process_ok("[% \$name %]" => "",        {name => 'foo'});
process_ok("[% \$name %]" => "7",       {name => 'foo', foo => 7});
process_ok("[% \$name.bar %]" => "",    {name => 'foo'});
process_ok("[% \$name.bar %]" => "",    {name => 'foo', foo => {}});
process_ok("[% \$name.bar %]" => "7",   {name => 'foo', foo => {bar => 7}});
process_ok("[% \$name().bar %]" => "7", {name => 'foo', foo => {bar => 7}});
process_ok("[% \$name.0 %]" => "7",     {name => 'foo', foo => [7, 2, 3]});
process_ok("[% \$name %]" => 7,         {name => 'foo', foo => sub { 7 }});
process_ok("[% \$name(7) %]" => 7,      {name => 'foo', foo => sub { $_[0] }});

process_ok("[% GET \$name %]" => "",      {name => 'foo'});
process_ok("[% GET \$name %]" => "7",     {name => 'foo', foo => 7});
process_ok("[% GET \$name.bar %]" => "",  {name => 'foo'});
process_ok("[% GET \$name.bar %]" => "",  {name => 'foo', foo => {}});
process_ok("[% GET \$name.bar %]" => "7", {name => 'foo', foo => {bar => 7}});
process_ok("[% GET \$name.0 %]" => "7",   {name => 'foo', foo => [7, 2, 3]});
process_ok("[% GET \$name %]" => 7,       {name => 'foo', foo => sub { 7 }});
process_ok("[% GET \$name(7) %]" => 7,    {name => 'foo', foo => sub { $_[0] }});

process_ok("[% \$name %]" => "",     {name => 'foo foo', foo => 7});
process_ok("[% GET \$name %]" => "", {name => 'foo foo', foo => 7});

process_ok("[% \${name} %]" => "",        {name => 'foo'});
process_ok("[% \${name} %]" => "7",       {name => 'foo', foo => 7});
process_ok("[% \${name}.bar %]" => "",    {name => 'foo'});
process_ok("[% \${name}.bar %]" => "",    {name => 'foo', foo => {}});
process_ok("[% \${name}.bar %]" => "7",   {name => 'foo', foo => {bar => 7}});
process_ok("[% \${name}().bar %]" => "7", {name => 'foo', foo => {bar => 7}});
process_ok("[% \${name}.0 %]" => "7",     {name => 'foo', foo => [7, 2, 3]});
process_ok("[% \${name} %]" => 7,         {name => 'foo', foo => sub { 7 }});
process_ok("[% \${name}(7) %]" => 7,      {name => 'foo', foo => sub { $_[0] }});

process_ok("[% GET \${name} %]" => "",      {name => 'foo'});
process_ok("[% GET \${name} %]" => "7",     {name => 'foo', foo => 7});
process_ok("[% GET \${name}.bar %]" => "",  {name => 'foo'});
process_ok("[% GET \${name}.bar %]" => "",  {name => 'foo', foo => {}});
process_ok("[% GET \${name}.bar %]" => "7", {name => 'foo', foo => {bar => 7}});
process_ok("[% GET \${name}.0 %]" => "7",   {name => 'foo', foo => [7, 2, 3]});
process_ok("[% GET \${name} %]" => 7,       {name => 'foo', foo => sub { 7 }});
process_ok("[% GET \${name}(7) %]" => 7,    {name => 'foo', foo => sub { $_[0] }});

process_ok("[% \${name} %]" => "",     {name => 'foo foo', foo => 7});
process_ok("[% GET \${name} %]" => "", {name => 'foo foo', foo => 7});

process_ok("[% foo.\$name %]" => '', {name => 'bar'});
process_ok("[% foo.\$name %]" => 7, {name => 'bar', foo => {bar => 7}});
process_ok("[% foo.\$name.baz %]" => '', {name => 'bar', bar => {baz => 7}});

process_ok("[% \"hi\" %]" => 'hi');
process_ok("[% 'hi' %]" => 'hi');
process_ok("[% \"hi \$foo\" %]"   => 'hi 7', {foo => 7});
process_ok("[% \"hi \${foo}\" %]" => 'hi 7', {foo => 7});
process_ok("[% 'hi \$foo' %]"   => 'hi $foo', {foo => 7});
process_ok("[% 'hi \${foo}' %]" => 'hi ${foo}', {foo => 7});

process_ok("[% \"hi \${foo.seven}\" %]"   => 'hi 7', {foo => $obj});
process_ok("[% \"hi \${foo.echo(7)}\" %]" => 'hi 7', {foo => $obj});


###----------------------------------------------------------------###
### variable SETting

process_ok("[% SET foo bar %][% foo %]" => '');
process_ok("[% SET foo = 1 %][% foo %]" => '1');
process_ok("[% SET foo = 1  bar = 2 %][% foo %][% bar %]" => '12');
process_ok("[% SET foo  bar = 1 %][% foo %]" => '');
process_ok("[% SET foo = 1 ; bar = 1 %][% foo %]" => '1');
process_ok("[% SET foo = 1 %][% SET foo %][% foo %]" => '');

process_ok("[% SET foo = [] %][% foo.0 %]" => "");
process_ok("[% SET foo = [1, 2, 3] %][% foo.1 %]" => 2);
process_ok("[% SET foo = {} %][% foo.0 %]" => "");
process_ok("[% SET foo = {1 => 2} %][% foo.1 %]" => "2") if ! $is_tt;
process_ok("[% SET foo = {'1' => 2} %][% foo.1 %]" => "2");

process_ok("[% SET name = 1 %][% SET foo = name %][% foo %]" => "1");
process_ok("[% SET name = 1 %][% SET foo = \$name %][% foo %]" => "");
process_ok("[% SET name = 1 %][% SET foo = \${name} %][% foo %]" => "");
process_ok("[% SET name = 1 %][% SET foo = \"\$name\" %][% foo %]" => "1");
process_ok("[% SET name = 1 foo = name %][% foo %]" => '1');
process_ok("[% SET name = 1 %][% SET foo = {\$name => 2} %][% foo.1 %]" => "2");
process_ok("[% SET name = 1 %][% SET foo = {\"\$name\" => 2} %][% foo.1 %]" => "2") if ! $is_tt;
process_ok("[% SET name = 1 %][% SET foo = {\${name} => 2} %][% foo.1 %]" => "2");

process_ok("[% SET name = 7 %][% SET foo = {'2' => name} %][% foo.2 %]" => "7");
process_ok("[% SET name = 7 %][% SET foo = {'2' => \"\$name\"} %][% foo.2 %]" => "7");

process_ok("[% SET name = 7 %][% SET foo = [1, name, 3] %][% foo.1 %]" => "7");
process_ok("[% SET name = 7 %][% SET foo = [1, \"\$name\", 3] %][% foo.1 %]" => "7");

process_ok("[% SET foo = { bar => { baz => [0, 7, 2] } } %][% foo.bar.baz.1 %]" => "7");

process_ok("[% SET foo.bar = 1 %][% foo.bar %]" => '1');
process_ok("[% SET foo.bar.baz.bing = 1 %][% foo.bar.baz.bing %]" => '1');
process_ok("[% SET foo.bar.2 = 1 %][% foo.bar.2 %] [% foo.bar.size %]" => '1 1');
process_ok("[% SET foo.bar = [] %][% SET foo.bar.2 = 1 %][% foo.bar.2 %] [% foo.bar.size %]" => '1 3');

process_ok("[% SET name = 'two' %][% SET \$name = 3 %][% two %]" => 3);
process_ok("[% SET name = 'two' %][% SET \${name} = 3 %][% two %]" => 3);
process_ok("[% SET name = 2 %][% SET foo.\$name = 3 %][% foo.2 %]" => 3);
process_ok("[% SET name = 2 %][% SET foo.\$name = 3 %][% foo.\$name %]" => 3);
process_ok("[% SET name = 2 %][% SET foo.\${name} = 3 %][% foo.2 %]" => 3);
process_ok("[% SET name = 2 %][% SET foo.\${name} = 3 %][% foo.2 %]" => 3);
process_ok("[% SET name = 'two' %][% SET \$name.foo = 3 %][% two.foo %]" => 3);
process_ok("[% SET name = 'two' %][% SET \${name}.foo = 3 %][% two.foo %]" => 3);
process_ok("[% SET name = 'two' %][% SET foo.\$name.foo = 3 %][% foo.two.foo %]" => 3);
process_ok("[% SET name = 'two' %][% SET foo.\${name}.foo = 3 %][% foo.two.foo %]" => 3);

process_ok("[% SET foo = [1..10] %][% foo.6 %]" => 7);
process_ok("[% SET foo = [10..1] %][% foo.6 %]" => '');
process_ok("[% SET foo = [-10..-1] %][% foo.6 %]" => -4);
process_ok("[% SET foo = [1..3..10] %][% foo.6 %]" => '');
process_ok("[% SET foo = [1..2..10] %][% foo.6 %]" => '');
process_ok("[% SET foo = [1,1..0..10] %][% foo.6 %]" => '');
process_ok("[% SET foo = [1..10, 21..30] %][% foo.12 %]" => 23)         if ! $is_tt;
process_ok("[% SET foo = [..100] bar = 7 %][% bar %][% foo.0 %]" => ''); # TODO - more consistent
process_ok("[% SET foo = [100..] bar = 7 %][% bar %][% foo.0 %]" => 7)  if ! $is_tt;
process_ok("[% SET foo = ['a'..'z'] %][% foo.6 %]" => 'g');
process_ok("[% SET foo = ['z'..'a'] %][% foo.6 %]" => '');
process_ok("[% SET foo = ['a'..'z'].reverse %][% foo.6 %]" => 't')      if ! $is_tt;

###----------------------------------------------------------------###
### CALL and DEFAULT

process_ok("[% DEFAULT foo = 7 %][% foo %]" => 7);
process_ok("[% SET foo = 5 %][% DEFAULT foo = 7 %][% foo %]" => 5);
process_ok("[% DEFAULT foo.bar.baz.bing = 6 %][% foo.bar.baz.bing %]" => 6);

my $t = 0;
process_ok("[% foo %]"      => 'hi', {foo => sub {$t++; 'hi'}});
process_ok("[% GET  foo %]" => 'hi', {foo => sub {$t++; 'hi'}});
process_ok("[% CALL foo %]" => '',   {foo => sub {$t++; 'hi'}});
ok($t == 3, "CALL method actually called var");

###----------------------------------------------------------------###
### virtual methods

process_ok("[% [0 .. 10].reverse.1 %]" => 9) if ! $is_tt;
process_ok("[% {a => 'A'}.a %]" => 'A') if ! $is_tt;
process_ok("[% 'This is a string'.length %]" => 16) if ! $is_tt;
process_ok("[% 123.length %]" => 3) if ! $is_tt;
process_ok("[% 123.2.length %]" => 5) if ! $is_tt;
process_ok("[% -123.2.length %]" => 6) if ! $is_tt;

###----------------------------------------------------------------###
### chomping

process_ok(" [% foo %]" => ' ');
process_ok(" [%- foo %]" => '');
process_ok("\n[%- foo %]" => '');
process_ok("\n [%- foo %]" => '');
process_ok("\n\n[%- foo %]" => "\n");
process_ok(" \n\n[%- foo %]" => " \n");
process_ok(" \n[%- foo %]" => " ") if ! $is_tt;
process_ok(" \n \n[%- foo %]" => " \n ") if ! $is_tt;

process_ok("[% foo %] " => ' ');
process_ok("[% foo -%] " => '') if ! $is_tt;
process_ok("[% foo -%]\n" => '');
process_ok("[% foo -%] \n" => '');
process_ok("[% foo -%]\n " => ' ');
process_ok("[% foo -%]\n\n\n" => "\n\n");
process_ok("[% foo -%] \n " => ' ');

###----------------------------------------------------------------###
### math operations

process_ok("[% 1 + 2 %]" => 3);
process_ok("[% (1 + 2) %]" => 3);
process_ok("[% 2 - 1 %]" => 1);
process_ok("[% -1 + 2 %]" => 1);
process_ok("[% 4 * 2 %]" => 8);
process_ok("[% 4 / 2 %]" => 2);
process_ok("[% 2 ** 3 %]" => 8) if ! $is_tt;
process_ok("[% 1 + 2 * 3 %]" => 7);
process_ok("[% 3 * 2 + 1 %]" => 7);
process_ok("[% (1 + 2) * 3 %]" => 9);
process_ok("[% 3 * (1 + 2) %]" => 9);
process_ok("[% 1 + 2 ** 3 %]" => 9) if ! $is_tt;
process_ok("[% 2 * 2 ** 3 %]" => 16) if ! $is_tt;
process_ok("[% SET foo = 1 %][% foo + 2 %]" => 3);
process_ok("[% SET foo = 1 %][% (foo + 2) %]" => 3);

###----------------------------------------------------------------###
### boolean operations

process_ok("[% 5 && 6 %]" => 6);
process_ok("[% 5 || 6 %]" => 5);
process_ok("[% 0 || 6 %]" => 6);
process_ok("[% 0 && 6 %]" => 0);
process_ok("[% 0 && 0 %]" => 0);

process_ok("[% 5 + (0 || 5) %]" => 10);

###----------------------------------------------------------------###
### blocks

process_ok("[% PROCESS foo %]" => '');
process_ok("[% BLOCK foo %]" => '');
process_ok("[% BLOCK foo %][% END %]" => '');
process_ok("[% BLOCK foo %]hi there[% END %]" => '');
process_ok("[% BLOCK foo %][% BLOCK foo %][% END %][% END %]" => '');
process_ok("[% BLOCK foo %]hi there[% END %][% PROCESS foo %]" => 'hi there');
process_ok("[% PROCESS foo %][% BLOCK foo %]hi there[% END %]" => 'hi there');
process_ok("[% BLOCK foo %]hi [% one %] there[% END %][% PROCESS foo %]" => 'hi ONE there', {one => 'ONE'});
process_ok("[% IF 1 %]Yes[% END %]" => 'Yes');
process_ok("[% IF 0 %]Yes[% END %]" => '');
process_ok("[% BLOCK foo %]hi [% IF 1 %]Yes[% END %] there[% END %]<<[% PROCESS foo %]>>" => '<<hi Yes there>>');

###----------------------------------------------------------------###
### comments

process_ok("[%# one %]" => '', {one => 'ONE'});
process_ok("[%#\n one %]" => '', {one => 'ONE'});
process_ok("[%-#\n one %]" => '', {one => 'ONE'})     if ! $is_tt;
process_ok("[% #\n one %]" => 'ONE', {one => 'ONE'});
process_ok("[%# BLOCK one %]" => '');
process_ok("[%# BLOCK one %]two" => 'two');
process_ok("[%# BLOCK one %]two[% END %]" => '');
process_ok("[%# BLOCK one %]two[% END %]three" => '');

###----------------------------------------------------------------###
### foreach, next, last

process_ok("[% FOREACH foo %]" => '');
process_ok("[% FOREACH foo %][% END %]" => '');
process_ok("[% FOREACH foo %]bar[% END %]" => '');
process_ok("[% FOREACH foo %]bar[% END %]" => 'bar', {foo => 1});
process_ok("[% FOREACH f IN foo %]bar[% f %][% END %]" => 'bar1bar2', {foo => [1,2]});
process_ok("[% FOREACH f = foo %]bar[% f %][% END %]" => 'bar1bar2', {foo => [1,2]});
process_ok("[% FOREACH f = [1,2] %]bar[% f %][% END %]" => 'bar1bar2');
process_ok("[% FOREACH f = [1..3] %]bar[% f %][% END %]" => 'bar1bar2bar3');
process_ok("[% FOREACH f = [{a=>'A'},{a=>'B'}] %]bar[% f.a %][% END %]" => 'barAbarB');
process_ok("[% FOREACH [{a=>'A'},{a=>'B'}] %]bar[% a %][% END %]" => 'barAbarB');
process_ok("[% FOREACH [{a=>'A'},{a=>'B'}] %]bar[% a %][% END %][% a %]" => 'barAbarB');
process_ok("[% FOREACH [1] %][% SET a = 1 %][% END %][% a %]" => '');
process_ok("[% FOREACH f = [1..3] %][% loop.count %]/[% loop.size %] [% END %]" => '1/3 2/3 3/3 ');
process_ok("[% FOREACH f = [1..3] %][% IF loop.first %][% f %][% END %][% END %]" => '1');
process_ok("[% FOREACH f = [1..3] %][% IF loop.last %][% f %][% END %][% END %]" => '3');
process_ok("[% FOREACH f = [1..3] %][% IF loop.first %][% NEXT %][% END %][% f %][% END %]" => '23');
process_ok("[% FOREACH f = [1..3] %][% IF loop.first %][% LAST %][% END %][% f %][% END %]" => '');
process_ok("[% FOREACH f = [1..3] %][% f %][% IF loop.first %][% NEXT %][% END %][% END %]" => '123');
process_ok("[% FOREACH f = [1..3] %][% f %][% IF loop.first %][% LAST %][% END %][% END %]" => '1');


###----------------------------------------------------------------###
### stop

process_ok("[% STOP %]" => '');
process_ok("One[% STOP %]Two" => 'One');
process_ok("[% FOREACH f = [1..3] %][% f %][% IF loop.first %][% STOP %][% END %][% END %]" => '1');
process_ok("[% FOREACH f = [1..3] %][% IF loop.first %][% STOP %][% END %][% f %][% END %]" => '');

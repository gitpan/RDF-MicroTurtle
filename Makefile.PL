use strict;
use warnings;

use inc::Module::Install;

my $dist = 'RDF-MicroTurtle';
my $fn   = 'lib/RDF/MicroTurtle/Parser.pm';

name                $dist;
perl_version_from   $fn;
version_from        $fn;
abstract_from       $fn;
readme_from         $fn;
author              'Toby Inkster <tobyink@cpan.org>';
license             'perl';

eval 'use HTML::Microformats;';
if ($@)
{
	warn "************************************************\n"
	   . "** HTML::Microformats is needed to parse MicroTurtle embedded in StatusNet RSS feeds.\n"
	   . "** You don't appear to have HTML::Microformats, but installling $dist anyway!\n"
	   . "************************************************\n";
}

requires            'CGI::Util'          => 0;
requires            'Data::UUID'         => 0;
requires            'Digest::SHA1'       => 0;
recommends          'HTML::Microformats' => 0;
requires            'LWP::UserAgent'     => 0;
requires            'RDF::Trine'         => '0.123';
requires            'RDF::TrineShortcuts'=> 0;
test_requires       'Test::More'         => '0.61';
requires            'Text::Balanced'     => 0;
requires            'URI'                => 0;
requires            'XML::Atom::OWL'     => 0;

resources(
	'homepage'   => "http://search.cpan.org/dist/$dist/",
	'repository' => "http://goddamn.co.uk/viewvc/perlmods/$dist/",
	'bugtracker' => "http://rt.cpan.org/Dist/Display.html?Queue=$dist",
	);
	
write_doap_changes;
write_doap_changes_xml;

include 'Test::Signature';
auto_install;
WriteAll(
	'meta' => 1,
	'sign' => 1,
	);

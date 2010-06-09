package RDF::MicroTurtle::Context;

use 5.008;
use common::sense;
use utf8;

use CGI::Util qw'escape';
use Data::UUID;
use RDF::TrineShortcuts qw':nodes rdf_statement';

our $VERSION = '0.001';

sub new
{
	my ($class, %args) = @_;
	
	my $uuid = Data::UUID->new->create_str;
	$args{'agent_uri'}  ||= "widget://$uuid/Agents#\%s";
	$args{'tag_uri'}    ||= "widget://$uuid/Tags#\%s";
	$args{'me_uri'}     ||= "widget://$uuid/Me";
	
	return bless \%args, $class;
}

sub agent_uri
{
	my ($self, $account_name) = @_;
	
	return sprintf($self->{'agent_uri'}, escape($account_name));
}

sub tag_uri
{
	my ($self, $tag) = @_;
	
	(my $canon_tag = lc $tag) =~ s/\-\_\.//g;
	return sprintf($self->{'tag_uri'}, escape($canon_tag));
}

sub me_uri
{
	my ($self) = @_;
	
	return $self->{'me_uri'};
}

sub agent_triples
{
	my ($self, $account_name) = @_;
	
	return (
		rdf_statement(
			rdf_resource($self->agent_uri($account_name)),
			rdf_resource('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'),
			rdf_resource('http://xmlns.com/foaf/0.1/Agent'),
			),
		rdf_statement(
			rdf_resource($self->agent_uri($account_name)),
			rdf_resource('http://xmlns.com/foaf/0.1/nick'),
			rdf_literal($account_name),
			),
		);
}

sub tag_triples
{
	my ($self, $tag) = @_;
	
	return (
		rdf_statement(
			rdf_resource($self->tag_uri($tag)),
			rdf_resource('http://www.w3.org/1999/02/22-rdf-syntax-ns#type'),
			rdf_resource('http://www.holygoat.co.uk/owl/redwood/0.1/tags/Tag'),
			),
		rdf_statement(
			rdf_resource($self->tag_uri($tag)),
			rdf_resource('http://www.holygoat.co.uk/owl/redwood/0.1/tags/name'),
			rdf_literal($tag),
			),
		);
}

sub tagging_triples
{
	my ($self, $thing, $tag) = @_;
	
	return (
		rdf_statement(
			rdf_node($thing),
			rdf_resource('http://www.holygoat.co.uk/owl/redwood/0.1/tags/taggedWithTag'),
			rdf_resource($self->tag_uri($tag)),
			),
		);
}

1;

=head1 NAME

RDF::MicroTurtle::Context - contextual hints for parsing MicroTurtle

=head1 VERSION

0.001

=head1 DESCRIPTION

MicroTurtle is an unusual serialisation of RDF in that it provides various tokens representing
people and tags/concepts which the parser expands to full URIs based on out-of-band contextual
knowledge.

This module provides a safe, albeit not very good, default context. Better contexts should be
written as subclasses of this one.

The constructor is called as:

  my $context = RDF::MicroTurtle::Context->new(%args);

All arguments are optional.

=over

=item * C<< $args{'me_uri'} >> - the full URI that "E<lt>#meE<gt>" will be expanded to when parsing MicroTurtle.

=item * C<< $args{'agent_uri'} >> - the template URI that "@somebody" will be expanded to when parsing MicroTurtle. This is a string containing "%s" which will be used to substitute an account name.

=item * C<< $args{'tag_uri'} >> - the template URI that "#hashtag" will be expanded to when parsing MicroTurtle. This is a string containing "%s" which will be used to substitute a hash tag.

=back

=head1 SUBCLASSING

Your C<new> constructor may be passed various details about the context of the
MicroTurtle data being parsed. It can pick and choose which details it wants to honour.

Two interesting arguments to the constructor are 'id' and 'model' which are an
RDF::Trine::Node and RDF::Trine::Model respectively. These are passed by
L<RDF::MicroTurtle::Feed> and contain the identifier for the feed entry currently
being parsed, and an RDF model of the RSS/Atom feed data itself.

The important methods to override are C<me_uri> (returns a URI that represents the
document author), C<agent_uri> (takes an account name, and returns a URI representing
the agent that holds the account), and C<tag_uri> (takes a hashtag minus the hash, and
returns a URI representing the concept that the hashtag denotes).

Other methods to override are C<agent_triples> (takes an account name, and returns an
array of RDF::Trine::Statemement objects describing the holder of the account),
C<tag_triples> (takes a hashtag minus the hash, and returns an array of RDF::Trine::Statement
objects describing the concept denoted by the hashtag) and C<tagging_triples> (takes a URI
or bnode identifier - starting with '_:' - and a hashtag, and returns an array of triples to indicate
that the thing identified by the URI or bnode has been tagged with that tag).

=head1 BUGS

Please report any bugs to L<http://rt.cpan.org/>.

=head1 SEE ALSO

L<RDF::MicroTurtle::Parser>.

L<http://www.perlrdf.org/>.

L<http://buzzword.org.uk/2009/microturtle/spec>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

Copyright (C) 2009-2010 by Toby Inkster

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

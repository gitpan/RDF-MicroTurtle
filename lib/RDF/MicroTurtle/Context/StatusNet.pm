package RDF::MicroTurtle::Context::StatusNet;

use 5.008;
use base qw'RDF::MicroTurtle::Context';
use common::sense;
use utf8;

use CGI::Util qw'escape';
use HTML::Microformats;
use RDF::TrineShortcuts;

our $VERSION = '0.001';

sub new
{
	my ($class, %args) = @_;
	
	die "Need to supply 'id'"    unless defined $args{'id'}    && $args{'id'}->isa('RDF::Trine::Node');
	die "Need to supply 'model'" unless defined $args{'model'} && $args{'model'}->isa('RDF::Trine::Model');
	
	return $class->SUPER::new(%args);
}

# this is a little ugly! maybe we can get this data into the feed properly!
sub agent_uri
{
	my ($self, $account_name) = @_;

	my $iter = $self->{'model'}->get_statements(
		$self->{'id'},
		RDF::Trine::Node::Resource->new("http://purl.org/rss/1.0/modules/content/encoded"),
		undef,
		RDF::Trine::Node::Nil->new,
		);
	
	while (my $st = $iter->next)
	{
		my $html = $st->object->literal_value;
		# base URL doesn't really matter, because all URLs in $html are absolute anyway.
		my $url  = $self->{'id'}->is_resource ? $self->{'id'}->uri : 'http://example.com/';
		
		my $doc  = HTML::Microformats->new_document($html, $url)->assume_profile('hCard');
		foreach my $hcard ($doc->objects('hCard'))
		{
			foreach my $nickname (@{$hcard->get_nickname})
			{
				if (lc $nickname eq lc $account_name)
				{
					my @urls = @{$hcard->get_url};
					return $urls[0];
				}
			}
		}
	}

	return $self->SUPER::agent_uri($account_name);
}

sub tag_uri
{
	my ($self, $tag) = @_;	
	(my $canon_tag = lc $tag) =~ s/\-\_\.//g;

	my $iter = $self->{'model'}->get_pattern(
		RDF::Trine::Pattern->new(
			RDF::Trine::Statement->new(
				$self->{'id'},
				RDF::Trine::Node::Resource->new('http://commontag.org/ns#tagged'),
				RDF::Trine::Node::Variable->new('tag'),
				),
			RDF::Trine::Statement->new(
				RDF::Trine::Node::Variable->new('tag'),
				RDF::Trine::Node::Resource->new('http://commontag.org/ns#label'),
				RDF::Trine::Node::Variable->new('label'),
				),
			),
		RDF::Trine::Node::Nil->new,
		);
	
	while (my $row = $iter->next)
	{
		next unless $row->{'tag'}->is_resource;
		next unless $row->{'label'}->is_literal;
		
		if (lc $row->{'label'}->literal_value eq $canon_tag
		||  lc $row->{'label'}->literal_value eq lc $tag)
		{
			return $row->{'tag'}->uri;
		}
	}

	return $self->SUPER::tag_uri($tag);
}

sub me_uri
{
	my ($self) = @_;
	
	my $iter = $self->{'model'}->get_statements(
		$self->{'id'},
		RDF::Trine::Node::Resource->new("http://xmlns.com/foaf/0.1/maker"),
		undef,
		RDF::Trine::Node::Nil->new,
		);
	
	while (my $st = $iter->next)
	{
		return $st->object->uri;
	}
	
	return $self->SUPER::me_uri;
}

sub agent_triples
{
	return qw();
}

sub tag_triples
{
	return qw();
}

1;

=head1 NAME

RDF::MicroTurtle::Context::StatusNet - contextual hints for parsing MicroTurtle in StatusNet RSS feeds

=head1 VERSION

0.001

=head1 SYNOPSIS

 use RDF::MicroTurtle::Feed;
 use RDF::MicroTurtle::Context::StatusNet;
 
 my $feed = RDF::MicroTurtle::Feed->new_from_url(
              'http://identi.ca/tag/mttl/rss',
              'RDF::MicroTurtle::Context::StatusNet');
 my $data = $feed->model;

=head1 BUGS

Please report any bugs to L<http://rt.cpan.org/>.

=head1 SEE ALSO

L<RDF::MicroTurtle::Context>.

L<http://www.perlrdf.org/>.

L<http://buzzword.org.uk/2009/microturtle/spec>, L<http://status.net/>, L<http://identi.ca/>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

Copyright (C) 2009-2010 by Toby Inkster

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8 or,
at your option, any later version of Perl 5 you may have available.

=cut

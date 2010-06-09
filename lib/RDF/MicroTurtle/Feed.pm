package RDF::MicroTurtle::Feed;

use 5.008;
use common::sense;

use LWP::UserAgent;
use RDF::MicroTurtle::Context;
use RDF::MicroTurtle::Parser;
use RDF::MicroTurtle::Feed::Atom;
use RDF::MicroTurtle::Feed::RSS10;

our $VERSION = '0.001';

sub new
{
	my ($class, $type, $data, $base, $context_class, @more) = @_;
	my $package = join '::', ($class, $type);
	$context_class ||= 'RDF::MicroTurtle::Context';
	return $package->new( $data, $base, $context_class, @more);
}

sub new_from_url
{
	my ($class, $url, $context_class, %args) = @_;
	
	my $ua = LWP::UserAgent->new(
		agent => $args{'user_agent'} || (__PACKAGE__ . ' '),
		);
	my $response = $ua->get($url, 'Accept'=>'application/rdf+xml,application/atom+xml,application/rss+xml');
	
	if ($response->content_type eq 'application/atom+xml')
	{
		return $class->new('Atom', $response->decoded_content, $response->base, $context_class);
	}
	elsif ($response->content_type eq 'application/rdf+xml')
	{
		return $class->new('RSS10', $response->decoded_content, $response->base, $context_class);
	}
	elsif ($response->content_type eq 'application/rss+xml'
	|| $response->content_type eq 'application/xml'
	|| $response->content_type eq 'text/xml')
	{
		warn "Don't understand non-1.0 versions of RSS. Attempting to treat as RSS 1.0...";
		return $class->new('RSS10', $response->decoded_content, $response->base, $context_class);
	}
	else
	{
		warn "Unrecognised content type: " . $response->content_type;
		die;
	}
}

sub model
{
	my ($self) = @_;
	return $self->{'model'};
}

sub microturtle_items
{
	my ($self) = @_;
	
}

sub _parse_items
{
	my ($self) = @_;
	my @fields = split /\s*\,\s*/, $self->{'order'};
	ITEM: foreach my $i (@{$self->{'items'} })
	{
		foreach my $f (@fields)
		{
			next ITEM unless $i->{$f} =~ /\#m?ttl/i;
			push @{$self->{'data_items'}}, $i;
			
			RDF::MicroTurtle::Parser->new(
					parsing_context => $self->{'context'}->new(id=>$i->{'id'}, model=>$self->{'model'}),
				)->parse_into_model(
					$i->{'link'},
					$i->{$f},
					$self->model,
					context => $i->{'id'},
				);
		}
	}
}

1;

=head1 NAME

RDF::MicroTurtle::Feed - find and parse MicroTurtle in an Atom or RSS feed

=head1 VERSION

0.001

=head1 DESCRIPTION

Loops through an Atom or RSS 1.0 feed finding entries containing MicroTurtle,
then parses them.

=head2 Constructors

Two constructors are provided:

  my $feed = RDF::MicroTurtle::Feed->new_from_url($url, $context_class);

Where C<$url> is the feed to retrieve and parse, and C<$context_class> is a string
containing the class name to use as a MicroTurtle parsing context.

  my $feed = RDF::MicroTurtle::Feed->new($type, $data, $base, $context_class);

Where C<$type> is either 'Atom' or 'RSS10' (case-sensitive), C<$data> is the raw
XML data as a string, and C<$base> is a base URL for resolving relative references.

=head2 Method

A method C<model> is provided to obtain the end result. The model contains
a mixture of quads and triples (triples are simply quads where the final component
is Nil). Triples represent the feed data itself; quads represent data obtained from
MicroTurtle parsing.

=head1 BUGS

Please report any bugs to L<http://rt.cpan.org/>.

=head1 SEE ALSO

L<RDF::MicroTurtle::Parser>, L<RDF::MicroTurtle::Context>.

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

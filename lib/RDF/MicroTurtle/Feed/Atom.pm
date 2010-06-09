package RDF::MicroTurtle::Feed::Atom;

use base qw'RDF::MicroTurtle::Feed';

use RDF::TrineShortcuts;
use XML::Atom::OWL;

our $VERSION = '0.001';

sub new
{
	my ($class, $content, $base, $context_class) = @_;
	
	my $self = bless {
		context   => $context_class,
		order     => 'title,summary,content',
		model     => XML::Atom::OWL->new($content, $base)->consume->graph,
		}, $class;

	$self->_find_items;
	$self->_parse_items;

	return $self;
}

sub _find_items
{
	my ($self) = @_;
	
	my $awol   = XML::Atom::OWL::AWOL_NS;
	my $sparql = <<SPARQL;
PREFIX awol: <$awol>
PREFIX iana: <urn:X-TODO:>
SELECT ?id ?title ?summary ?content ?contenttype
WHERE {
	?entry a awol:Entry ;
		awol:id ?id .
	OPTIONAL { ?entry awol:title [ awol:text ?title ] . }
	OPTIONAL { ?entry awol:summary [ awol:text ?summary ] . }
	OPTIONAL { ?entry awol:content [ awol:body ?content ; awol:type ?contenttype ] . }
	OPTIONAL { ?entry iana:self ?self . }
}
SPARQL

	my $results = rdf_query($sparql, $self->model);

	while (my $row = $results->next)
	{
		my $x = {};
		$x->{'id'}       = $row->{'id'};
		$x->{'title'}    = $row->{'title'}->literal_value
			if defined $row->{'title'} && $row->{'title'}->is_literal;
		$x->{'summary'}  = $row->{'summary'}->literal_value
			if defined $row->{'summary'} && $row->{'summary'}->is_literal;
		$x->{'content'}  = $row->{'content'}->literal_value
			if defined $row->{'content'} && $row->{'content'}->is_literal
			&& defined $row->{'contenttype'} && $row->{'contenttype'}->is_literal
			&& lc $row->{'contenttype'} eq 'text';
		$x->{'link'}     = $row->{'self'}->uri
			if defined $row->{'self'} && $row->{'self'}->is_resource;
		$x->{'link'}   ||= $row->{'id'}->literal
			if $row->{'id'}->is_literal;
		$x->{'link'}   ||= $row->{'entry'}->uri
			if $row->{'entry'}->is_resource;
		
		push @{ $self->{'items'} }, $x;
	}
}

1;

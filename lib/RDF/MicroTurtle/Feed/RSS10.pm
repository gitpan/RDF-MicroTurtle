package RDF::MicroTurtle::Feed::RSS10;

use base qw'RDF::MicroTurtle::Feed';

use RDF::TrineShortcuts;

our $VERSION = '0.001';

sub new
{
	my ($class, $content, $base, $context_class) = @_;
	
	my $self = bless {
		context   => $context_class,
		order     => 'title,description',
		model     => RDF::Trine::Model->temporary_model,
		}, $class;
	RDF::Trine::Parser::RDFXML->new->parse_into_model($base, $content, $self->{'model'});
	
	$self->_find_items;
	$self->_parse_items;
	
	return $self;
}

sub _find_items
{
	my ($self) = @_;

	my $sparql = <<SPARQL;
PREFIX rss: <http://purl.org/rss/1.0/>
SELECT ?id ?title ?content
WHERE {
	?id a rss:item ;
		rss:title ?title .
	OPTIONAL { ?id rss:description ?description . }
	OPTIONAL { ?id rss:link ?link . }
}
SPARQL

	my $results = rdf_query($sparql, $self->model);

	while (my $row = $results->next)
	{
		my $x = {};
		$x->{'id'}       = $row->{'id'};
		$x->{'title'}    = $row->{'title'}->literal_value
			if defined $row->{'title'} && $row->{'title'}->is_literal;
		$x->{'description'} = $row->{'description'}->literal_value
			if defined $row->{'description'} && $row->{'description'}->is_literal;
		$x->{'link'}     = $row->{'link'}->literal_value
			if defined $row->{'link'} && $row->{'link'}->is_literal;
		$x->{'link'}   ||= $row->{'id'}->uri
			if $row->{'id'}->is_resource;
		
		push @{ $self->{'items'} }, $x;
	}
}

1;

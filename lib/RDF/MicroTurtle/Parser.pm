package RDF::MicroTurtle::Parser;

use 5.008;
use base qw'RDF::Trine::Parser';
use common::sense;
use utf8;

use Data::UUID;
use Digest::SHA1 qw'sha1_hex';
use LWP::UserAgent;
use RDF::MicroTurtle::Context;
use RDF::TrineShortcuts qw':nodes rdf_statement';
use Text::Balanced qw(extract_bracketed extract_delimited);
use URI;

our $VERSION = '0.001';

BEGIN
{
	our $count = 0;
	
	# Certain prefixes are hard-coded. This list is part of the MicroTurtle spec.
	# (Or it will be if a spec gets written.) The list has a number of good,
	# general-purpose vocabs, plus a number which have been chosen because they
	# seem good matches for the type of topics frequently discussed in microblogs.
	#
	# For other prefixes, prefix.cc's service is used, but that is not a very
	# stable way of doing things.
	our $expand = {
		'bio'     => 'http://purl.org/vocab/bio/0.1/' ,
		'cc'      => 'http://creativecommons.org/ns#' ,
		'ccold'   => 'http://web.resource.org/cc/' ,
		'ccrel'   => 'http://creativecommons.org/ns#' ,
		'dc'      => 'http://purl.org/dc/terms/' ,
		'dc11'    => 'http://purl.org/dc/elements/1.1/' ,
		'dcterms' => 'http://purl.org/dc/terms/' ,
		'doac'    => 'http://ramonantonio.net/doac/0.1/#' ,
		'doap'    => 'http://usefulinc.com/ns/doap#' ,
		'foaf'    => 'http://xmlns.com/foaf/0.1/' ,
		'geo'     => 'http://www.w3.org/2003/01/geo/wgs84_pos#' , 
		'ical'    => 'http://www.w3.org/2002/12/cal/icaltzd#' ,
		'lac'     => 'http://laconi.ca/ont/' ,
		'like'    => 'http://ontologi.es/like#' ,
		'log'     => 'http://www.w3.org/2000/10/swap/log#' ,
		'mo'      => 'http://purl.org/ontology/mo/' ,
		'ov'      => 'http://open.vocab.org/terms/' ,
		'owl'     => 'http://www.w3.org/2002/07/owl#' ,
		'rdf'     => 'http://www.w3.org/1999/02/22-rdf-syntax-ns#' ,
		'rdfg'    => 'http://www.w3.org/2004/03/trix/rdfg-1/' ,
		'rdfs'    => 'http://www.w3.org/2000/01/rdf-schema#' ,
		'rel'     => 'http://purl.org/vocab/relationship/' ,
		'rev'     => 'http://purl.org/stuff/rev#' ,
		'rss'     => 'http://purl.org/rss/1.0/' ,
		'sioc'    => 'http://rdfs.org/sioc/ns#' ,
		'skos'    => 'http://www.w3.org/2004/02/skos/core#' ,
		'tags'    => 'http://www.holygoat.co.uk/owl/redwood/0.1/tags/' ,
		'vcard'   => 'http://www.w3.org/2006/vcard/ns#' ,
		'wot'     => 'http://xmlns.com/wot/0.1/' ,
		'xfn'     => 'http://vocab.sindice.com/xfn#' ,
		'xhv'     => 'http://www.w3.org/1999/xhtml/vocab#' ,
		'xsd'     => 'http://www.w3.org/2001/XMLSchema#' ,
		};
	
	$RDF::Trine::Parser::parser_names{'microturtle'}       = __PACKAGE__;
	$RDF::Trine::Parser::parser_names{'mttl'}              = __PACKAGE__;
	$RDF::Trine::Parser::parser_names{'µttl'}              = __PACKAGE__;
	$RDF::Trine::Parser::media_types{'text/x-microturtle'} = __PACKAGE__;
	$RDF::Trine::Parser::media_types{'text/microturtle'}   = __PACKAGE__;
}

# options:
#   * no_agent_triples - suppresses implicit triples of the form { <@person> a foaf:Agent ; foaf:nick "person" . }
#   * no_tag_triples - suppresses implicit triples of the form { <#hashtag> a tags:Tag ; tags:name "hashtag" . }
#   * no_tagging_triples - suppresses implicit triples of the form { <thing> tags:taggedWithTag <#hashtag> . }
#   * parsing_context - an instance of type RDF::MicroTurtle::Context, or a subclass.
sub new
{
	my ($class, %args) = @_;
	$args{'parsing_context'} ||= RDF::MicroTurtle::Context->new;
	$args{'bnode_prefix'} = Data::UUID->new->create_hex;
	
	my $self = bless \%args, $class;
	
	return $self;
}

sub parse
{
	my ($proto, $base_uri, $rdf, $handler) = @_;
	$proto = $proto->new unless ref $proto;
	
	my $data = $proto->microturtle($base_uri, $rdf);
	
	foreach my $triple (@{ $data->{triples} })
	{
		$handler->( $triple );
	}

	unless ($proto->{'no_agent_triples'})
	{
		foreach my $agent (@{ $data->{agents} })
		{
			foreach my $triple ($proto->{'parsing_context'}->agent_triples($agent))
			{
				$handler->( $triple );
			}
		}
	}
	
	my $tags_used = {};
	while (my ($uri, $tags) = each %{ $data->{tags} })
	{
		my $thing = $uri =~ /^<(.*)>$/ ? $1 : $uri;
		
		foreach my $tag (@$tags)
		{
			unless ($proto->{'no_tagging_triples'})
			{
				foreach my $triple ($proto->{'parsing_context'}->tagging_triples($thing, $tag))
				{
					$handler->( $triple );
				}
			}
			$tags_used->{$tag}++;
		}
	}
	foreach my $tag (keys %$tags_used)
	{
		unless ($proto->{'no_tag_triples'})
		{
			foreach my $triple ($proto->{'parsing_context'}->tag_triples($tag))
			{
				$handler->( $triple );
			}
		}
	}
}

sub microturtle
{
	my ($self, $base, $text) = @_;
	
	my ($comment, $mttl);
	
	if ($text =~ /^(.*)#m?ttl(.+)$/)
	{
		($comment, $mttl) = ($1, $2);
	}
	else
	{
		($comment, $mttl) = (undef, $text);		
	}
	
	$base ||= sprintf('widget://%s.microturtle/self', sha1_hex($text));
	
	my $parsed  = $self->_mttl_parse($mttl, $base);
	my @triples = map { _trine_statement($_) } @{ $parsed->{'triples'} };
	
	$parsed->{'triples'} = \@triples;
	
	return $parsed;
}

sub _trine_statement
{
	my ($triple) = @_;
	my ($s, $p, $o, $rev) = @$triple;
	
	($s, $o) = ($o, $s) if $rev;
	
	my ($subject, $predicate, $object);

	if ($s =~ /^<(.*)>$/)
	{
		$subject = rdf_resource($1);
	}
	else
	{
		$subject = rdf_node($s);
	}

	if ($p =~ /^<(.*)>$/)
	{
		$predicate = rdf_resource($1);
	}
	else
	{
		$predicate = rdf_node($p);
	}

	if (ref $o && $o->isa('RDF::MicroTurtle::Parser::Literal'))
	{
		$object = rdf_literal($o->{value}, lang=>$o->{lang}, datatype=>$o->{dturi});
	}
	elsif ($o =~ /^<(.*)>$/)
	{
		$object = rdf_resource($1);
	}
	else
	{
		$object = rdf_node($o);
	}
	
	return rdf_statement($subject, $predicate, $object);
}

sub _mttl_parse
{
	my ($self, $mttl, $base) = @_;
	
	my $agents = [];
	my @raw    = $self->_mttl_tokenize($mttl);
	my @tokens = $self->_mttl_expand($base, $agents, @raw);
	
	my $triples;
	my $tags = {};
	my $current_triple;
	my $isof = 0;
	
	while (my $t = shift @tokens)
	{
		if ((ref $t) && $t->isa('RDF::MicroTurtle::Parser::Literal'))
		{
			push @$current_triple, $t;
		}
		elsif ($t =~ /^#(\S+)$/)
		{
			#hashtags 
			if (defined $current_triple->[0])
			{
				push @{$tags->{$current_triple->[0]}}, $1;
			}
			else
			{
				push @{$tags->{'<'.$base.'>'}}, $1;
			}
		}
		elsif ($t eq '.')
		{
			if (defined $current_triple->[2] && !defined $current_triple->[3])
			{
				push @$current_triple, 'REV' if $isof;
				push @$triples, $current_triple;
				$isof = 0;
			}
			$current_triple = [];
		}
		elsif ($t eq ';')
		{
			if (defined $current_triple->[2] && !defined $current_triple->[3])
			{
				push @$current_triple, 'REV' if $isof;
				push @$triples, $current_triple;
				$isof = 0;
			}
			$current_triple = [$current_triple->[0]];
		}
		elsif ($t eq ',')
		{
			if (defined $current_triple->[2] && !defined $current_triple->[3])
			{
				push @$current_triple, 'REV' if $isof;
				push @$triples, $current_triple;
			}
			$current_triple = [$current_triple->[0] , $current_triple->[1]];
		}
		elsif ($t eq '[]')
		{
			push @$current_triple, '_:'.$self->_random_bnode;
		}
		elsif ($t eq 'has')
		{
			# noop
		}
		elsif ($t eq 'is')
		{
			# noop
		}
		elsif ($t eq 'of')
		{
			$isof = 1;
		}
		elsif ($t eq '[')
		{
			my $anon = '_:'.$self->_random_bnode;
			my $r = $self->_mttl_parse_bracketted(\@tokens, $anon, $triples, $tags);
			foreach my $triple (@{ $r->{'triples'} })
			{
				push @$triples, $triple;
			}
			push @$current_triple, $anon;
		}
		else
		{
			push @$current_triple, $t;
		}
	}
	
	if (defined $current_triple->[2] && !defined $current_triple->[3])
	{
		push @$current_triple, 'REV' if $isof;
		push @$triples, $current_triple;
		$isof = 0;
	}
	
	return {
		'triples' => $triples ,
		'tags'    => $tags ,
		'agents'  => $agents ,
		};
}


sub _mttl_parse_bracketted
{
	my ($self, $tokens, $subject, $triples, $tags) = @_;
	
	my $current_triple = [$subject];
	my $isof = 0;
	
	while (my $t = shift @$tokens)
	{
		last if (!ref $t) && ($t eq ']');
	
		if ((ref $t) && $t->isa('RDF::MicroTurtle::Parser::Literal'))
		{
			push @$current_triple, $t;
		}
		elsif ($t =~ /^#(\S+)$/)
		{
			push @{$tags->{$subject}}, $1;  #hashtags
		}
		elsif ($t eq ';')
		{
			if (defined $current_triple->[2] && !defined $current_triple->[3])
			{
				push @$current_triple, 'REV' if $isof;
				push @$triples, $current_triple;
				$isof = 0;
			}
			$current_triple = [$subject];
		}
		elsif ($t eq ',')
		{
			if (defined $current_triple->[2] && !defined $current_triple->[3])
			{
				push @$current_triple, 'REV' if $isof;
				push @$triples, $current_triple;
			}
			$current_triple = [$subject, $current_triple->[1]];
		}
		elsif ($t eq '[]')
		{
			push @$current_triple, '_:'.$self->_random_bnode;
		}
		elsif ($t eq '[')
		{
			my $anon = '_:'.$self->_random_bnode;
			my $r = $self->_mttl_parse_bracketted($tokens, $anon, $triples, $tags);
			foreach my $triple (@{ $r->{'triples'} })
			{
				push @$triples, $triple;
			}
			push @$current_triple, $anon;
		}
		else
		{
			push @$current_triple, $t;
		}
	}
	
	if (defined $current_triple->[2] && !defined $current_triple->[3])
	{
		push @$current_triple, 'REV' if $isof;
		push @$triples, $current_triple;
		$isof = 0;
	}
		
	return {
		'triples' => $triples ,
		'tags'    => $tags
		};
}

sub _mttl_tokenize
{
	my ($self, $ts) = @_;
	my @rv;
	
	if ($ts =~ /^[\s\r\n]*\{.*\}[\s\r\n]*$/s)
	{
		$ts =~ s/^([\s\r\n]*\{)|(\}[\s\r\n]*$)//gs;
	}
	
	while (length $ts)
	{
		$ts =~ s/^[\s\r\n]+//s;
		
		if ($ts =~ /^([\-\+]?([0-9]+\.[0-9]*e[\-\+]?[0-9]+))/i
		||     $ts =~ /^([\-\+]?(\.[0-9]+e[\-\+]?[0-9]+))/i
		||     $ts =~ /^([\-\+]?([0-9]+e[\-\+]?[0-9]+))/i)
		{
			push @rv, RDF::MicroTurtle::Parser::Literal->new($1, undef, 'xsd:double');
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^([\-\+]?([0-9]+\.[0-9]*))/
		||     $ts =~ /^([\-\+]?(\.[0-9]+))/)
		{
			push @rv, RDF::MicroTurtle::Parser::Literal->new($1, undef, 'xsd:decimal');
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^([\-\+]?([0-9]+))/)
		{
			push @rv, RDF::MicroTurtle::Parser::Literal->new($1, undef, 'xsd:integer');
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^([\.\,\;])/)
		{
			push @rv, $1;
			$ts = substr($ts, length $1);
		}
# Don't have placeholder variables.
#		elsif ($ts =~ /^([\?\$]\S+)/)
#		{
#			push @rv, $1;
#			$ts = substr($ts, length $1);
#		}
# But have hashtags...
		elsif ($ts =~ /^([\#][A-Za-z0-9_\.-]+)/)
		{
			push @rv, $1;
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^(<[^>]*>)/)
		{
			push @rv, $1;
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ m'^(https?://\S+)'i)
		{
			push @rv, '<'.$1.'>';
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^["']/)
		{
			my ($string, $lang, $dt, $dturi);
			($string, $ts) = extract_delimited($ts, substr($ts, 0, 1));
			
			if ($ts =~ /^(
				\@
				(
					(([A-Z]{2,8})|i|x)		# primary
					(\-[A-Z]{4})?			# script
					(\-([A-Z]{2})|([0-9]{3}))?	# region
					(\-[A-Z0-9]+)*			# other bits
				)
				)/ix)
			{
				$lang = lc $2;
				$ts = substr($ts, length $1);
			}
			if ($ts =~ /^(\^\^<([^>]*)>)/)
			{
				$dturi = $2;
				$ts = substr($ts, length $1);
			}
			elsif ($ts =~ /^(\^\^([^:]*:[^\s\,\;]*))/)
			{
				$dt = $2;
				$ts = substr($ts, length $1);
			}
			
			$string = substr($string, 1, (length $string)-2);
			
			push @rv, RDF::MicroTurtle::Parser::Literal->new($string, $lang, $dt, $dturi);
		}
		elsif ($ts =~ /^_:([^\s\,\;]*)/)
		{
			push @rv, '_:x'.$self->{'bnode_prefix'}.'x'.$1;
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^([^\s\,\;]*:[^\s\,\;]*)/)
		{
			push @rv, $1;
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^a\b/)
		{
			push @rv, '<http://www.w3.org/1999/02/22-rdf-syntax-ns#type>';
			$ts = substr($ts, 1);
		}
		elsif ($ts =~ /^of\b/)
		{
			push @rv, 'of';
			$ts = substr($ts, 2);
		}
		elsif ($ts =~ /^is\b/)
		{
			push @rv, 'is';
			$ts = substr($ts, 2);
		}
		elsif ($ts =~ /^has\b/)
		{
			push @rv, 'has';
			$ts = substr($ts, 3);
		}
		elsif ($ts =~ /^=>/)
		{
			push @rv, '<http://www.w3.org/2000/10/swap/log#implies>';
			$ts = substr($ts, 2);
		}
		elsif ($ts =~ /^<=/)
		{
			push @rv, ('is', '<http://www.w3.org/2000/10/swap/log#implies>', 'of');
			$ts = substr($ts, 2);
		}
		elsif ($ts =~ /^at\b/)
		{
			push @rv, '<http://www.w3.org/2003/01/geo/wgs84_pos#location>';
			$ts = substr($ts, 2);
		}
		elsif ($ts =~ /^says\b/)
		{
			push @rv, '<http://open.vocab.org/terms/quote>';
			$ts = substr($ts, 4);
		}
		elsif ($ts =~ /^gist\b/)
		{
			push @rv, '<http://purl.org/dc/terms/abstract>';
			$ts = substr($ts, 4);
		}
		elsif ($ts =~ /^=/)
		{
			push @rv, '<http://www.w3.org/2002/07/owl#sameAs>';
			$ts = substr($ts, 1);
		}
		elsif ($ts =~ /^\s*([→])/)
		{
			push @rv, '<http://xmlns.com/foaf/0.1/homepage>';
			$ts = substr($ts, length($1));
		}
		elsif ($ts =~ /^\s*([←])/)
		{
			push @rv, ('<http://xmlns.com/foaf/0.1/primaryTopic>');
			$ts = substr($ts, length($1));
		}
		elsif ($ts =~ /^\s*([♥♡❤])/)
		{
			push @rv, '<http://ontologi.es/like#likes>';
			$ts = substr($ts, length($1));
		}
		elsif ($ts =~ /^(true|false)\b/i)
		{
			push @rv, RDF::MicroTurtle::Parser::Literal->new($1, undef, 'xsd:boolean');
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^(\@[A-Za-z0-9][A-Za-z0-9-]*)\b/)
		{
			push @rv, "<$1>";
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^(\[\s*\])/)
		{
			push @rv, '[]';
			$ts = substr($ts, length $1);
		}
		elsif ($ts =~ /^([\[\]\(\)])/)
		{
			push @rv, $1;
			$ts = substr($ts, 1);
		}
		else
		{
			warn "Possible Turtle tokenisation problem!\n";
			push @rv, "???ERRORCOND???";
			return @rv;
		}
	}
	
	return @rv;
}

sub _mttl_expand
{
	my ($self, $base, $agent_list, @terms) = @_;
	my $uri   = URI->new($base);
	my @rv;
	
	while (my $term = shift @terms)
	{
		if ((ref $term) && $term->isa('RDF::MicroTurtle::Parser::Literal'))
		{
			push @rv, $term;
		}
		elsif ($term =~ /^<\@(.+)>$/)
		{
			push @$agent_list, $1;
			push @rv, $self->{'parsing_context'}->agent_uri($1);
		}
		elsif ($term =~ /^<#me>$/)
		{
			push @rv, $self->{'parsing_context'}->me_uri;
		}
		elsif ($term =~ /^([A-Za-z0-9_-]+):(\S+)$/
		&&     $term !~ /^_:/)
		{
			my ($prefix, $suffix) = ($1, $2);
			if (!defined $RDF::MicroTurtle::Parser::expand->{$prefix})
			{
				my $txt = LWP::UserAgent->new->get("http://prefix.cc/$prefix.txt.plain")->decoded_content;
				chomp $txt;
				my (undef, $uri) = split /\s/, $txt;
				$RDF::MicroTurtle::Parser::expand->{$prefix} = $uri;
			}
			push @rv, '<' . $RDF::MicroTurtle::Parser::expand->{$prefix} . $suffix . '>';
		}
		elsif ($term =~ /^<(.+)>$/)
		{
			my $termuri = URI->new_abs($1, $uri);
			push @rv, "<$termuri>";
		}
		elsif ($term =~ /^<>$/)
		{
			push @rv, "<$uri>";
		}
		else
		{
			push @rv, $term;
		}
	}
	
	return @rv;
}

sub _random_bnode
{
	my ($self) = @_;
	return sprintf('z%sz%02d', $self->{'bnode_prefix'}, $RDF::MicroTurtle::count++);
}

1;

package RDF::MicroTurtle::Parser::Literal;

use overload '""' => sub { return $_[0]->{'value'}; } ;

sub new
{
	my $class = shift;
	my $value = shift;
	my $lang  = shift;
	my $dt    = shift;
	my $dturi = shift;
	
	if (!$dturi && $dt =~ /^([^:]+):(.*)$/)
	{
		my ($prefix, $suffix) = ($1, $2);
		if (!defined $RDF::MicroTurtle::Parser::expand->{$prefix})
		{
			my $txt = LWP::UserAgent->new->get("http://prefix.cc/$prefix.txt.plain")->decoded_content;
			chomp $txt;
			my (undef, $uri) = split /\s/, $txt;
			$RDF::MicroTurtle::expand->{$prefix} = $uri;
		}
		
		$dturi = $RDF::MicroTurtle::expand->{$prefix} . $suffix;
	}
	
	my $self = {
		'value' => $value ,
		'lang'  => (lc $lang) ,
		'dt'    => $dt ,
		'dturi' => $dturi ,
		};
	
	bless $self, $class;
}

1;
__END__

=head1 NAME

RDF::MicroTurtle::Parser - parse MicroTurtle

=head1 VERSION

0.001

=head1 DESCRIPTION

This is a subclass of L<RDF::Trine::Parser> and supports the methods
C<parse_into_model>, C<parse_file_into_model>, C<parse_file> and
C<parse>.

=head2 Constructor

Can be constructued using the usual RDF::Trine method:

  my $parser = RDF::Trine::Parser->new('microturtle', %args);

Or:

  my $parser = RDF::MicroTurtle::Parser->new(%args);

The most important argument is C<< $args{'parsing_context'} >> which is an instance of
L<RDF::MicroTurtle::Context> (or any subclasses). It may be omitted in which case a new
RDF::MicroTurtle::Context object will be created.

Other arguments are booleans to suppress certain implicit contextual triples.

=over 4

=item * C<< $args{'no_agent_triples'} >> - suppresses implicit triples of the form { E<lt>@personE<gt> a foaf:Agent ; foaf:nick "person" . }

=item * C<< $args{'no_tag_triples'} >> - suppresses implicit triples of the form { E<lt>#hashtagE<gt> a tags:Tag ; tags:name "hashtag" . }

=item * C<< $args{'no_tagging_triples'} >> - suppresses implicit triples of the form { E<lt>thingE<gt> tags:taggedWithTag E<lt>#hashtagE<gt> . }

=back

=head1 BUGS

Please report any bugs to L<http://rt.cpan.org/>.

=head1 SEE ALSO

L<RDF::Trine::Parser>.

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

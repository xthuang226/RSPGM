#!/usr/bin/perl
use warnings;
use strict;
use feature 'say';

use Mojolicious::Lite;
use DBI;
use Mojo::JSON qw(decode_json encode_json);
use Scalar::Util qw(looks_like_number);
plugin 'RenderFile';
plugin 'RemoteAddr';




# color setting
my @color = qw/FF5959 FF6363 FF6D6D FF7777 FF8181 FF8B8B FF9595 FF9F9F FFA9A9 FFB3B3 FFBDBD/;

# global variables
my $nodes_global;
my $edges_global;
my $query_type;			# string, the name user typed
my @query_name;			# array, the name user typed
my @query_id;			# corresponding id of the typing name
my @name_total_global;


# connect to database
my $dbh = DBI->connect("dbi:SQLite:dbname=data/ppi.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;

# shortcut for use in template
helper db => sub { $dbh };

# read auto cre list
#~ my $sql = '
	#~ SELECT locus FROM nodes_name WHERE locus != \'-\'
	#~ UNION
	#~ SELECT symbol FROM nodes_name WHERE symbol != \'-\'
#~ ';
#~ my $sql = '
	#~ SELECT symbol FROM nodes_name WHERE symbol != \'-\'
#~ ';
my $sql = '
	SELECT locus_symbol FROM nodes_name WHERE locus_symbol != \'-\'
';

my $sth = $dbh->prepare( $sql );
$sth->execute();
my $gene_names = $sth->fetchall_arrayref;

my @json_rows;
foreach my $gn (@$gene_names){
	push @json_rows, encode_json {('name', $$gn[0])};
}

my $genenames = '['.(join (',', @json_rows)).']';


# In this step, query the specific information from the database by the user input. Return nodes and edges information.
helper search => sub {
	my $self = shift;
	my ($name) = @_;
	my $sth;
	
	if (defined $name){
		my $sql_nodes;
		my $sql_rows;
		my ($nodes, $rows);
		@query_name = split(/,/, $name);
		
		foreach (@query_name){
			my $id = &get_id($_, $dbh);
			push @query_id, $id if defined $id;
		}
		
		if (scalar @query_id == 1){
			
			my $key = $query_id[0];
			
			$sql_nodes = '
					SELECT id,locus,locus_symbol,symbol,gene_id,wormbase_id FROM
					(select id_a from ppi_score_info where cast(? as integer) in (id_a, id_b)
					union
					select id_b from ppi_score_info where cast(? as integer) in (id_a, id_b))as res
					LEFT JOIN nodes_name
					ON res.id_a = nodes_name.id
			';
			
			$sql_rows = '
					with linked(name) as (
						select id_a from ppi_score_info where cast(? as integer) in (id_a, id_b)
						union
						select id_b from ppi_score_info where cast(? as integer) in (id_a, id_b)					
					)

					SELECT locus_symbol_a,locus_symbol as locus_symbol_b,rspgm_score,pubmed_id FROM

					(SELECT id_a,locus as locus_a,locus_symbol as locus_symbol_a,id_b,rspgm_score,pubmed_id FROM ppi_score_info

					LEFT JOIN nodes_name
					ON ppi_score_info.id_a = nodes_name.id)as res

					LEFT JOIN nodes_name
					ON res.id_b = nodes_name.id

					WHERE id_a IN (SELECT * FROM linked) AND id_b IN (SELECT * FROM linked)
			';

			$sth = eval { $self->db->prepare( $sql_nodes ) } || return undef;
			$sth->execute($key,$key);
			$nodes = $sth->fetchall_arrayref;

			$sth = eval { $self->db->prepare( $sql_rows ) } || return undef;
			$sth->execute($key,$key);
			$rows = $sth->fetchall_arrayref;

		}else{
			my $key = join (',', @query_id);
			$sql_nodes = '
				SELECT * FROM nodes_name
				WHERE id in ('.$key.')
			';
			
			$sql_rows = '
					SELECT locus_symbol_a,locus_symbol as locus_symbol_b,rspgm_score,pubmed_id FROM

					(SELECT id_a,locus as locus_a,locus_symbol as locus_symbol_a,id_b,rspgm_score,pubmed_id FROM ppi_score_info

					LEFT JOIN nodes_name
					ON ppi_score_info.id_a = nodes_name.id)as res

					LEFT JOIN nodes_name
					ON res.id_b = nodes_name.id

					WHERE id_a IN ('.$key.') AND id_b IN ('.$key.')
			';
			
			$sth = eval { $self->db->prepare( $sql_nodes ) } || return undef;
			$sth->execute();
			$nodes = $sth->fetchall_arrayref;

			$sth = eval { $self->db->prepare( $sql_rows ) } || return undef;
			$sth->execute();
			$rows = $sth->fetchall_arrayref;
		}

		return ($nodes, $rows);
	}
};


any '/' => sub {
	my $c = shift;
	$c->stash(names => $genenames);
	$c->render('rspgm_index');

	my $ip = $c->remote_addr;
	my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
	& ip_info($ip, $dbh_ip);
	$dbh_ip->disconnect;
};

any '/search' => sub {
	my $self = shift;
	$query_type = $self->param('gene_name');
	$query_type =~ s/\s+//g;
	
	my ($nodes, $rows)= $self->search($query_type);

	if (scalar @$nodes != 0){
		$nodes_global = &to_json($nodes,'nodes');
		$edges_global = &to_json($rows,'edges');
	}else{
		undef $query_type;
		undef @query_name;
		undef @query_id;
		undef @name_total_global;
		undef $nodes_global;
		undef $edges_global;
	}
	
	$self->stash( rows => $rows, name_total => \@name_total_global, nodes => $nodes);
	$self->render('rspgm_search');
	
	undef $query_type;
	undef @query_name;
	undef @query_id;
	undef @name_total_global;
	
	my $ip = $self->remote_addr;
	my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
	& ip_search($ip, $dbh_ip);
	$dbh_ip->disconnect;
};

any '/graph' => sub {
	my $c = shift;
	$c->stash(nodes => $nodes_global, edges => $edges_global);
	$c->render('rspgm_graph');
};

any '/download' => sub {
	my $c = shift;
	$c->render('rspgm_download');
};

any '/download/PPIs_csv' => sub {
	my $self = shift;
	my $file = "PPIs_score_info.csv";
	$self->render_file('filepath' => "./download/$file");

	my $ip = $self->remote_addr;
	my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
	& ip_download($ip, $dbh_ip);
	$dbh_ip->disconnect;
};
any '/download/PPIs_tab' => sub {
	my $self = shift;
	my $file = "PPIs_score_info.txt";
	$self->render_file('filepath' => "./download/$file");

	my $ip = $self->remote_addr;
	my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
	& ip_download($ip, $dbh_ip);
	$dbh_ip->disconnect;
};

any '/download/pathway_csv' => sub {
	my $self = shift;
	my $file = "Interaction_path_inference.csv";
	$self->render_file('filepath' => "./download/$file");

	my $ip = $self->remote_addr;
	my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
	& ip_download($ip, $dbh_ip);
	$dbh_ip->disconnect;
};

any '/download/all' => sub {
	my $self = shift;
	my $file = "RSPGM.zip";
	$self->render_file('filepath' => "./download/$file");

	my $ip = $self->remote_addr;
	my $dbh_ip = DBI->connect("dbi:SQLite:dbname=data/ip_record.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
	& ip_download($ip, $dbh_ip);
	$dbh_ip->disconnect;
};

my @viewppis;
open (INPUT,'download/PPIs_score_info.txt')||die "Error!\n$!";
foreach (<INPUT>){
	my @array = split(/\t/,$_);
	push @viewppis, \@array;
}
close INPUT;

any '/download/PPIs_view' => sub {
  my $self = shift;
  $self->stash( viewppis => \@viewppis);
  $self->render('rspgm_PPIs_view');
};

any '/pathway' => sub {
	my $c = shift;
	$c->render('rspgm_pathway');
};

any '/pathway_graph' => sub {
	my $c = shift;
	$c->render('rspgm_pathway_graph');
};


app->start;





sub to_json {
	my ($rows, $para) = @_;
	my @json_rows;
	my $result = 'null';
	
	if ($para eq 'nodes'){
		
		undef @name_total_global;
		
		if (@query_id > 1){
			foreach my $row (@$rows){
				my @name_info;
				push @name_info, ($$row[1],$$row[3],$$row[4],$$row[5]);
				push @name_total_global, \@name_info;
				push @json_rows, encode_json {('data'), {('id', $$row[2])}, ('css'), {('background-color', '#14446A', 'width', 40, 'height', 40)}};
			}
		}else{
			foreach my $row (@$rows){
				my @name_info;
				push @name_info, ($$row[1],$$row[3],$$row[4],$$row[5]);
				push @name_total_global, \@name_info;
				if ($$row[0] == $query_id[0]){
					push @json_rows, encode_json {('data'), {('id', $$row[2])}, ('css'), {('background-color', '#14446A', 'width', 70, 'height', 70)}};
				}else{
					push @json_rows, encode_json {('data'), {('id', $$row[2])}, ('css'), {('background-color', '#B3767E', 'width', 40, 'height', 40)}};
				}
			}
		}

		$result = '['.(join (',', @json_rows)).']' if scalar @$rows != 0;
	}else{
		foreach my $row (@$rows){
			my $scale = int(10*$$row[2]); # 0-10 integer
			my $color = '#'.$color[10-$scale];
			my $width = $scale + 4;
			my $opacity = 0.5*$scale + 0.5;
			push @json_rows, encode_json {('data'), {('id', $$row[0].$$row[1], 'source', $$row[0], 'target', $$row[1], 'weight', $$row[2])}, ('css'), {('line-color', $color, 'width', $width, 'opacity', $opacity)}};
		}

		$result = '['.(join (',', @json_rows)).']' if scalar @$rows != 0;
	}
	
	return $result;
}

### get gene id in table nodes_name
sub get_id {
	my ($query, $dbh) = @_;
	
	my $sql = '
		SELECT id FROM nodes_name
		WHERE upper(?) in (upper(locus),upper(locus_symbol),upper(symbol),gene_id,upper(wormbase_id))
	';
	
	my $sth = $dbh->prepare( $sql );
	$sth->execute($query);
	my @ary = $sth->fetchrow_array;
	return $ary[0];
}


### update_remote_ip_info
sub ip_info {
	my ($ip, $dbh) = @_;
	
	my $sql = '
		SELECT * FROM ip_info
		WHERE remoter_ip IS ?
	';
	
	my $sth = $dbh->prepare( $sql );
	$sth->execute($ip);
	
	my $query_ip_info = $sth->fetchall_arrayref;
	
	my $row = $$query_ip_info[0];
	my $count = $$row[1];
	my $access_history = $$row[3];
	
	if (scalar @$query_ip_info == 1){
		$count += 1;
		$access_history =~ s/}/ ; /;
		
		my $sql = '
			UPDATE ip_info
			SET counter = '.$count.', last_access = (SELECT datetime(\'now\',\'localtime\')), access_history = \''.$access_history.'\'||(SELECT datetime(\'now\',\'localtime\'))||\'}\'
			WHERE remoter_ip IS ?
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}else{
		my $sql = '
			INSERT INTO ip_info (remoter_ip,counter,last_access,access_history)
			VALUES (?, 1, (SELECT datetime(\'now\',\'localtime\')), \'{\'||(SELECT datetime(\'now\',\'localtime\'))||\'}\')
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}
}

### update_remote_ip_info_download_file
sub ip_download {
	my ($ip, $dbh) = @_;
	
	my $sql = '
		SELECT * FROM ip_download
		WHERE remoter_ip IS ?
	';
	
	my $sth = $dbh->prepare( $sql );
	$sth->execute($ip);
	
	my $query_ip_info = $sth->fetchall_arrayref;
	
	my $row = $$query_ip_info[0];
	my $count = $$row[1];
	my $access_history = $$row[3];
	
	if (scalar @$query_ip_info == 1){
		$count += 1;
		$access_history =~ s/}/ ; /;
		
		my $sql = '
			UPDATE ip_download
			SET counter = '.$count.', last_access = (SELECT datetime(\'now\',\'localtime\')), access_history = \''.$access_history.'\'||(SELECT datetime(\'now\',\'localtime\'))||\'}\'
			WHERE remoter_ip IS ?
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}else{
		my $sql = '
			INSERT INTO ip_download (remoter_ip,counter,last_access,access_history)
			VALUES (?, 1, (SELECT datetime(\'now\',\'localtime\')), \'{\'||(SELECT datetime(\'now\',\'localtime\'))||\'}\')
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}
}


### update_remote_ip_search_
sub ip_search {
	my ($ip, $dbh) = @_;
	
	my $sql = '
		SELECT * FROM ip_search
		WHERE remoter_ip IS ?
	';
	
	my $sth = $dbh->prepare( $sql );
	$sth->execute($ip);
	
	my $query_ip_info = $sth->fetchall_arrayref;
	
	my $row = $$query_ip_info[0];
	my $count = $$row[1];
	my $access_history = $$row[3];
	
	if (scalar @$query_ip_info == 1){
		$count += 1;
		$access_history =~ s/}/ ; /;
		
		my $sql = '
			UPDATE ip_search
			SET counter = '.$count.', last_access = (SELECT datetime(\'now\',\'localtime\')), access_history = \''.$access_history.'\'||(SELECT datetime(\'now\',\'localtime\'))||\'}\'
			WHERE remoter_ip IS ?
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}else{
		my $sql = '
			INSERT INTO ip_search (remoter_ip,counter,last_access,access_history)
			VALUES (?, 1, (SELECT datetime(\'now\',\'localtime\')), \'{\'||(SELECT datetime(\'now\',\'localtime\'))||\'}\')
		';
		my $sth = $dbh->prepare( $sql );
		$sth->execute($ip);
	}
}

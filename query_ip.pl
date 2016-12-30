use strict;
use warnings;
use 5.016;
use DBI;
use LWP::UserAgent;
use Encode;

my $par = <STDIN>;
chomp $par;

# connect to database
my $dbh = DBI->connect("dbi:SQLite:dbname=data/RSPGM/ppi.db3","","",{ RaiseError => 1 }) or die $DBI::errstr;
my $sql = '
	SELECT * FROM ip_info
	LEFT JOIN ip_location
	ON ip_info.remoter_ip = ip_location.remoter_ip
	ORDER BY last_access
';

my $sth = $dbh->prepare( $sql );
$sth->execute();

my $row = $sth->fetchall_arrayref;

foreach (@$row){
	my @locations;
	say "\n-------------------------------------------------------------------------";
	my $ip_info = $_;
	printf "IP: %s \t Count: %d \t Last: %s \n", $$ip_info[0],$$ip_info[1],$$ip_info[2];
	if (defined $$ip_info[5]){
		my $tmp = $$ip_info[5];
		$tmp = decode("utf8", $tmp);
		@locations = split(/ ; /, encode("gb2312", $tmp));
	}else{
		@locations = & ip_location ($$ip_info[0]);
		
		my $sql = '
			INSERT INTO ip_location (remoter_ip,location)
			VALUES (?, ?)
		';

		my $sth = $dbh->prepare( $sql );
		$sth->execute($$ip_info[0],decode("gb2312", join(' ; ',@locations)));
		
	}
	print "\n";
	map{say}@locations;
	print "\n";
	
	if ($par =~ /h/){
		my $ac_his = $$ip_info[3];
		$ac_his =~ s/[{}]//g;
		my @ac_his = split (/ ; /, $ac_his);
		map {say} @ac_his if scalar @ac_his > 1;
	}
}

print "\n\nPress 'q' to exit: ";

while (){
	my $flag = <STDIN>;
	chomp $flag;
	last if $flag eq 'q';
}


undef $sth;

$dbh->disconnect;
undef $dbh;




sub ip_location {
	my ($ip) = @_;
	my %res;

	my $ua = LWP::UserAgent->new;
	$ua->agent('Mozilla/5.0');
	$ua->cookie_jar({});
	
	my $url1 = "http://www.query-ip.com/";
	my $url2 = "http://www.ip138.com/ips138.asp";
	my $url3 = "http://www.ip.cn/index.php?ip=$ip";
	
	my $response = $ua->post( $url1,
		[
			ip => $ip
		]
	);
	if ($response->is_success) {
		my $content = $response->decoded_content;
		if ($content =~ /is located in <strong>([^<>]+)<\/strong>/){
			my $key = $1;
			$key =~ s/\s+/ /g;
			$key =~ s/^\s+//;
			$key =~ s/\s+$//;
			$res{$key} = 1;
		}
	}else {
		warn $response->status_line;
	}


	# $response = $ua->post( $url2,
	# 	[
	# 		ip => $ip,
	# 		action => 2
	# 	]
	# );
	# if ($response->is_success) {
	# 	my $content = $response->decoded_content;
		
	# 	while ($content =~ s/<li>[^<>]+£º([^<>]+)<\/li>//){
	# 		my $key = $1;
	# 		$key =~ s/\s+/ /g;
	# 		$key =~ s/^\s+//;
	# 		$key =~ s/\s+$//;
	# 		$res{$key} = 1;
	# 	}
		
	# }else {
	# 	warn $response->status_line;
	# }

	$response = $ua->get( $url3	);
	if ($response->is_success) {
		my $content = $response->decoded_content;
		$content = encode("gb2312", $content);
		
		if ($content =~ /À´×Ô£º(.+)<\/p><\/div>/){
			my @res = split (/<\/p><p>/,$1);
			foreach (@res){
				my $key = $_;
				$key =~ s/\s+/ /g;
				$key =~ s/GeoIP://g;
				$key =~ s/^\s+//;
				$key =~ s/\s+$//;
				$res{$key} = 1;
			}
		}
		
	}else {
		warn $response->status_line;
	}

	return keys %res;
}


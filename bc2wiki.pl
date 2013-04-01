#!/opt/local/bin/perl
use REST::Client;
use JSON;

# Data::Dumper makes it easy to see what the JSON returned actually looks like
# when converted into Perl data structures.
use Data::Dumper;
use MIME::Base64;
use Config::Simple;
use POSIX qw(strftime);
use Template;
use Encode;
use SOAP::Lite;
use utf8;

# https://developer.atlassian.com/display/FECRUDEV/Writing+a+REST+Client+in+Perl

sub toList {
	my $data = shift;
	my $key  = shift;
	if ( ref( $data->{$key} ) eq 'ARRAY' ) {
		$data->{$key};
	}
	elsif ( ref( $data->{$key} ) eq 'HASH' ) {
		[ $data->{$key} ];
	}
	else {
		[];
	}
}
if ( $#ARGV ne 1 ) {
	print "usage: $0 <config_file> <projectId>\n";
	exit 1;
}

my $cfg = new Config::Simple( $ARGV[0] );

# BC stuff
my $username     = $cfg->param("bc.username");
my $accountId    = $cfg->param("bc.accountId");
my $password     = $cfg->param("bc.password");
my $projectId    = $ARGV[1];
my $basecampHost = 'https://basecamp.com';
my $baseURL      = '/' . $accountId . '/api/v1';
my $headers      = {
	Accept           => 'application/json',
	'User-Agent'     => 'bc2wiki tool (' . $username . ')',
	=> Authorization => 'Basic ' . encode_base64( $username . ':' . $password )
};

# Confluence Stuff
my $cfUsername      = $cfg->param("confluence.username");
my $cfpassword      = $cfg->param("confluence.password");
my $confluenceHost  = $cfg->param("confluence.host");


my $soap =
  SOAP::Lite->service( $cfg->param("confluence.host") )->encoding('UTF-8');

my $cfToken = $soap->login( $cfUsername, $cfpassword );

# try to fetch the import space. If the space does not exists, then try to create a new one.
$soap->call( "removeSpace", $cfToken, $cfg->param("confluence.spaceKey") );
my $importSpace =
  $soap->getSpace( $cfToken, $cfg->param("confluence.spaceKey") );

if ( !defined $importSpace ) {
	print "** confluence import space does not exist. Trying to create one.\n";

	my $remoteSpace = {
		'name' => SOAP::Data->type(
			'string' => value => $cfg->param("confluence.spaceName")
		),
		'key' => SOAP::Data->type(
			'string' => value => $cfg->param("confluence.spaceKey")
		),
		'description' => SOAP::Data->type(
			'string' => value => $cfg->param("confluence.spaceDescription")
		),
	};

	#
	#		$serializer = SOAP::Serializer->new();
	#		   $serializer->readable('true');
	#		   $xml = $serializer->serialize($element);
	#		   print $xml;
	#

	$importSpace =
	  $soap->call( "addSpace", $cfToken, $remoteSpace );
	if ( $importSpace->fault ) {
		print
"* failed to create import space due to fault code $importSpace->faultcode and reason \"$importSpace->faultstring\"";
		exit -1;
	}

	print "** created import space.\n";
}
else {
	print "** import space exists.\n";
}

# create our placeholder page
my $date = strftime "%c", localtime;

my $topPage = $soap->call(
	'storePage',
	$cfToken,
	{
		parentId => $importSpace->result->{'homePage'},
		space    => SOAP::Data->type(
			'string' => value => $importSpace->result->{'key'}
		),
		title =>
		  SOAP::Data->type( 'string' => value => "Import Page " . $date ),
		content => SOAP::Data->type(
			'string' => value =>
'<ac:macro ac:name="info"><ac:rich-text-body>This is a placeholder page.</ac:rich-text-body></ac:macro>'
		)
	}
);
die $topPage->faultstring if ( $topPage->fault );

my $tt = Template->new( { ENCODING => 'utf8' } );

my $client = REST::Client->new();
$client->setHost($basecampHost);
$client->GET( $baseURL . '/projects/' . $projectId . '/topics.json', $headers );
my $response = from_json( $client->responseContent(), { utf8 => 1 } );

#my $topics = toList($response->{'reviews'},'reviewData');
foreach my $topic (@$response) {
	my $id          = $topic->{'id'};
	my $topicableId = $topic->{'topicable'}->{'id'};
	my $title       = $topic->{'title'};
	my $created_at  = $topic->{'created_at'};

	# let fetch all messages
	if ( $topic->{'topicable'}->{'type'} eq 'Message' ) {
		print "** handling message ($id) - $title\n";

		# ok this is a message
		#print Dumper $topic;
		$client->GET(
			$baseURL
			  . '/projects/'
			  . $projectId
			  . '/messages/'
			  . $topicableId . '.json',
			$headers
		);
		$response = from_json( $client->responseContent(), { utf8 => 1 } );
		my $ccontent = "";

		#print "\tsubject : $response->{'subject'}\n";
		#print "\tcreated : $response->{'created_at'}\n";
		#print "\tcreator : $response->{'creator'}->{'name'}\n";
		#print "\tcontent : $response->{'content'}\n";

		$tt->process( 'templates/message',
			{ topic => $topic, comments => toList( $response, 'comments' ) },
			\$ccontent )
		  || die $tt->error;

		#		print Dumper $ccontent;
		#		exit 0;
		#
		#print "\n$ccontent\n";

		my $messagePage = $soap->call(
			'storePage',
			$cfToken,
			{
				parentId => $topPage->result->{'id'},
				space    => SOAP::Data->type(
					'string' => value => $importSpace->result->{'key'}
				),
				title => SOAP::Data->type(
					'string' => value => $response->{'subject'}
				),
				content => SOAP::Data->type( 'string' => value => $ccontent )
			}
		);
		$ccontent = "";

	}
}


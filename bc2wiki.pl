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

#
sub storePage {
	my $soapclient = shift;
	my $authToken  = shift;
	my $spaceKey   = shift;
	my $parentId   = shift;
	my $pageTitle  = shift;
	my $content    = shift;

	return $soapclient->call(
		'storePage',
		$authToken,
		{
			parentId => $parentId,
			space    => SOAP::Data->type( 'string' => value => $spaceKey ),
			title    => SOAP::Data->type( 'string' => value => $pageTitle ),
			content  => SOAP::Data->type( 'string' => value => $content )
		}
	);
}

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

sub handleBaseCampTopics {
	my $client   = shift;
	my $response = from_json( $client->responseContent(), { utf8 => 1 } );

	foreach my $topic (@$response) {
		my $id          = $topic->{'id'};
		my $topicableId = $topic->{'topicable'}->{'id'};
		my $title       = $topic->{'title'};
		my $topicType   = $topic->{'topicable'}->{'type'};
		print "** handling topic ($id) - $title\n";
		next;

		# let fetch all messages
		if ( $topicType eq 'Message' ) {
			print "** handling message ($id) - $title\n";

			$client->GET(
				$baseURL
				  . '/projects/'
				  . $projectId
				  . '/messages/'
				  . $topicableId . '.json',
				$headers
			);
			$response = from_json( $client->responseContent(), { utf8 => 1 } );

			#		print Dumper $response;
			#		exit 0;
			my $ccontent = "";

			$tt->process(
				'templates/message',
				{
					topic   => $topic,
					message => $response
				},
				\$ccontent
			  )
			  || die $tt->error;

			my $messagePage = storePage(
				$soap, $cfToken,
				$importSpace->result->{'key'},
				$topPage->result->{'id'},
				$response->{'subject'}, $ccontent
			);

			$ccontent = "";

		}
		elsif ( $topicType eq 'Todo' ) {
			print "** handling Todo ($id) - $title\n";
			$client->GET(
				$baseURL
				  . '/projects/'
				  . $projectId
				  . '/todos/'
				  . $topicableId . '.json',
				$headers
			);
			$response = from_json( $client->responseContent(), { utf8 => 1 } );

			#		print Dumper $response;
			#		exit 0;
			my $ccontent = "";

			$tt->process(
				'templates/todo',
				{
					topic   => $topic,
					message => $response
				},
				\$ccontent
			  )
			  || die $tt->error;

			my $messagePage = storePage(
				$soap, $cfToken,
				$importSpace->result->{'key'},
				$topPage->result->{'id'},
				'Todo : ' . $response->{'content'}, $ccontent
			);

			$ccontent = "";

		}
		elsif ( $topicType eq 'Forward' ) {
			print "** handling Forward ($id) - $title\n";

			$client->GET(
				$baseURL
				  . '/projects/'
				  . $projectId
				  . '/forwards/'
				  . $topicableId . '.json',
				$headers
			);
			$response = from_json( $client->responseContent(), { utf8 => 1 } );

			#		print Dumper $response;
			#		exit 0;
			my $ccontent = "";

			$tt->process(
				'templates/forward',
				{
					topic   => $topic,
					message => $response
				},
				\$ccontent
			  )
			  || die $tt->error;

			my $messagePage = storePage(
				$soap, $cfToken,
				$importSpace->result->{'key'},
				$topPage->result->{'id'},
				'Forward : ' . $response->{'subject'}, $ccontent
			);

			$ccontent = "";
		}
		elsif ( $topicType eq 'CalendarEvent' ) {
			print "** handling CalendarEvent ($id) - $title\n";

			$client->GET(
				$baseURL
				  . '/projects/'
				  . $projectId
				  . '/calendar_events/'
				  . $topicableId . '.json',
				$headers
			);
			$response = from_json( $client->responseContent(), { utf8 => 1 } );

			#		print Dumper $response;
			#		exit 0;
			my $ccontent = "";

			$tt->process(
				'templates/calendar_events',
				{
					topic   => $topic,
					message => $response
				},
				\$ccontent
			  )
			  || die $tt->error;

			my $messagePage = storePage(
				$soap,
				$cfToken,
				$importSpace->result->{'key'},
				$topPage->result->{'id'},
				'Calendar Event : ' . $response->{'summary'},
				$ccontent
			);

			$ccontent = "";
		}
		else {
			print "$topic->{'topicable'}->{'type'}\n";
		}
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
my $cfUsername     = $cfg->param("confluence.username");
my $cfpassword     = $cfg->param("confluence.password");
my $confluenceHost = $cfg->param("confluence.host");

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

	$importSpace = $soap->call( "addSpace", $cfToken, $remoteSpace );
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

my $topPage = storePage(
	$soap,
	$cfToken,
	$importSpace->result->{'key'},
	$importSpace->result->{'homePage'},
	"Import Page " . $date,
'<ac:macro ac:name="info"><ac:rich-text-body>This is a placeholder page.</ac:rich-text-body></ac:macro><p><ac:macro ac:name="children"><ac:parameter ac:name="excerpt">true</ac:parameter><ac:parameter ac:name="all">true</ac:parameter></ac:macro></p>'
);

die $topPage->faultstring if ( $topPage->fault );

my $tt = Template->new( { ENCODING => 'utf8' } );

my $client = REST::Client->new();
$client->setHost($basecampHost);
$client->GET( $baseURL . '/projects/' . $projectId . '/topics.json', $headers );

if ( $client->responseCode() eq '200' ) {
	handleBaseCampTopics($client);
}

my $page = 1;
while ( $client->responseCode() eq '200' && length($client->responseContent()) > 10) {
	print $page;
	print "\n";
	$client->GET(
		$baseURL . '/projects/' . $projectId . '/topics.json?page=' . $page,
		$headers );
	if ( $client->responseCode() eq '200' && length($client->responseContent()) > 10) {
		handleBaseCampTopics($client);
	}
	$page++;
}


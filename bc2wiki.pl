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

#use SOAP::Lite +trace => 'debug';
use utf8;
require LWP::UserAgent;

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

# create our placeholder page(s)

my $discussionsPage = storePage(
	$soap,
	$cfToken,
	$importSpace->result->{'key'},
	$importSpace->result->{'homePage'},
	"Discussions",
'<ac:macro ac:name="info"><ac:rich-text-body>This is a placeholder page.</ac:rich-text-body></ac:macro><p><ac:macro ac:name="children"><ac:parameter ac:name="excerpt">true</ac:parameter><ac:parameter ac:name="all">true</ac:parameter></ac:macro></p>'
);

die $discussionsPage->faultstring if ( $discussionsPage->fault );

my $forwardsPage = storePage(
	$soap,
	$cfToken,
	$importSpace->result->{'key'},
	$importSpace->result->{'homePage'},
	"Forwards",
'<ac:macro ac:name="info"><ac:rich-text-body>This is a placeholder page.</ac:rich-text-body></ac:macro><p><ac:macro ac:name="children"><ac:parameter ac:name="excerpt">true</ac:parameter><ac:parameter ac:name="all">true</ac:parameter></ac:macro></p>'
);

die $forwardsPage->faultstring if ( $forwardsPage->fault );

my $todosPage = storePage(
	$soap,
	$cfToken,
	$importSpace->result->{'key'},
	$importSpace->result->{'homePage'},
	"ToDos",
'<ac:macro ac:name="info"><ac:rich-text-body>This is a placeholder page.</ac:rich-text-body></ac:macro><p><ac:macro ac:name="children"><ac:parameter ac:name="excerpt">true</ac:parameter><ac:parameter ac:name="all">true</ac:parameter></ac:macro></p>'
);

die $todosPage->faultstring if ( $todosPage->fault );

my $calendarEventsPage = storePage(
	$soap,
	$cfToken,
	$importSpace->result->{'key'},
	$importSpace->result->{'homePage'},
	"Calendar Events",
'<ac:macro ac:name="info"><ac:rich-text-body>This is a placeholder page.</ac:rich-text-body></ac:macro><p><ac:macro ac:name="children"><ac:parameter ac:name="excerpt">true</ac:parameter><ac:parameter ac:name="all">true</ac:parameter></ac:macro></p>'
);

die $calendarEventsPage->faultstring if ( $calendarEventsPage->fault );

my $uploadsPage = storePage(
	$soap,
	$cfToken,
	$importSpace->result->{'key'},
	$importSpace->result->{'homePage'},
	"Uploads",
'<ac:macro ac:name="info"><ac:rich-text-body>This is a placeholder page.</ac:rich-text-body></ac:macro><p><ac:macro ac:name="children"><ac:parameter ac:name="excerpt">true</ac:parameter><ac:parameter ac:name="all">true</ac:parameter></ac:macro></p>'
);

die $uploadsPage->faultstring if ( $uploadsPage->fault );

my $tt = Template->new( { ENCODING => 'utf8' } );

my $client = REST::Client->new();
$client->setHost($basecampHost);

# iterate through topics

my $page = 1;

while(1) {
	$client->GET(
		$baseURL . '/projects/' . $projectId . '/topics.json?page=' . $page,
		$headers );
	my $res  =  $client->responseContent();
	last if $res eq '[]';
	handleBaseCampTopics( $client, $projectId );
	$page++;
}
exit;



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

sub handleAttachment {
	my $ua         = shift;
	my $soapclient = shift;
	my $uaUsername = shift;
	my $uaPassword = shift;
	my $attachment = shift;
	my $pageId     = shift;
	my $authToken  = shift;

	my $request = HTTP::Request->new( GET => $attachment->{url} );
	$request->authorization_basic( $uaUsername, $uaPassword );

	my $data = $ua->request($request);
	if ( $data->is_success ) {

		$remoteAttachmentElement = SOAP::Data->name(
			"remoteAttachmentDetails" => \SOAP::Data->value(
				SOAP::Data->name( 'comment' => '' )->type('string'),
				SOAP::Data->name(
					'contentType' => $attachment->{content_type}
				  )->type('string'),
				SOAP::Data->name(
					'fileName' => $attachment->{key} . $attachment->{name}
				  )->type('string'),
				SOAP::Data->name( 'title' => $attachment->{name} )
				  ->type('string'),
			)
		)->type('tns2:RemoteAttachment');

		return $soapclient->call(
			'addAttachment',
			$authToken,
			SOAP::Data->value($pageId)->type('long'),
			$remoteAttachmentElement,
			SOAP::Data->value( ( $data->decoded_content ) )
			  ->type('base64Binary')
		);

	}
	else {
		die $data->status_line;
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

		my $ua = LWP::UserAgent->new;
		$ua->timeout(20);
		$ua->env_proxy;

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
				$discussionsPage->result->{'id'},
				$response->{'subject'}, $ccontent
			);

			# handle message attachment

			my $topLevelAttachments = toList( $response, 'attachments' );

			foreach my $attachment (@$topLevelAttachments) {
				print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
				handleAttachment(
					$ua,                        $soap,
					$cfg->param("bc.username"), $cfg->param("bc.password"),
					$attachment,                $messagePage->result->{'id'},
					$cfToken
				);

			}

			# handle comment attachment

			my $comments = toList( $response, 'comments' );

			foreach my $comment (@$comments) {
				my $attachments = toList( $comment, 'attachments' );
				foreach my $attachment (@$attachments) {
					print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
					handleAttachment(
						$ua,
						$soap,
						$cfg->param("bc.username"),
						$cfg->param("bc.password"),
						$attachment,
						$messagePage->result->{'id'},
						$cfToken
					);

				}

			}

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
				$todosPage->result->{'id'},
				'Todo : ' . $response->{'content'}, $ccontent
			);

			# handle comment attachment

			my $comments = toList( $response, 'comments' );

			foreach my $comment (@$comments) {
				my $attachments = toList( $comment, 'attachments' );
				foreach my $attachment (@$attachments) {
					print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
					handleAttachment(
						$ua,
						$soap,
						$cfg->param("bc.username"),
						$cfg->param("bc.password"),
						$attachment,
						$messagePage->result->{'id'},
						$cfToken
					);

				}

			}

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
				$soap,
				$cfToken,
				$importSpace->result->{'key'},
				$forwardsPage->result->{'id'},
				'Forward : ' . $response->{'subject'},
				$ccontent
			);

			# handle forward attachment

			my $topLevelAttachments = toList( $response, 'attachments' );

			foreach my $attachment (@$topLevelAttachments) {
				print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
				handleAttachment(
					$ua,                        $soap,
					$cfg->param("bc.username"), $cfg->param("bc.password"),
					$attachment,                $messagePage->result->{'id'},
					$cfToken
				);

			}

			# handle comment attachment

			my $comments = toList( $response, 'comments' );

			foreach my $comment (@$comments) {
				my $attachments = toList( $comment, 'attachments' );
				foreach my $attachment (@$attachments) {
					print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
					handleAttachment(
						$ua,
						$soap,
						$cfg->param("bc.username"),
						$cfg->param("bc.password"),
						$attachment,
						$messagePage->result->{'id'},
						$cfToken
					);

				}

			}

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
				$calendarEventsPage->result->{'id'},
				'Calendar Event : ' . $response->{'summary'},
				$ccontent
			);

			# handle comment attachment

			my $comments = toList( $response, 'comments' );

			foreach my $comment (@$comments) {
				my $attachments = toList( $comment, 'attachments' );
				foreach my $attachment (@$attachments) {
					print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
					handleAttachment(
						$ua,
						$soap,
						$cfg->param("bc.username"),
						$cfg->param("bc.password"),
						$attachment,
						$messagePage->result->{'id'},
						$cfToken
					);

				}

			}

			$ccontent = "";
		} elsif ( $topicType eq 'Upload' ) {
			print "** handling Upload ($id) - $title\n";
			$client->GET(
				$baseURL
				  . '/projects/'
				  . $projectId
				  . '/uploads/'
				  . $topicableId . '.json',
				$headers
			);
			$response = from_json( $client->responseContent(), { utf8 => 1 } );

			#		print Dumper $response;
			#		exit 0;
			my $ccontent = "";

			$tt->process(
				'templates/upload',
				{
					topic   => $topic,
					message => $response
				},
				\$ccontent
			  )
			  || die $tt->error;

			my $topLevelAttachments = toList( $response, 'attachments' );
			
			my $messagePage = storePage(
				$soap,
				$cfToken,
				$importSpace->result->{'key'},
				$uploadsPage->result->{'id'},
				'Upload : ' . @$topLevelAttachments[0]->{'name'},
				$ccontent
			);
			
			# handle message attachment
			
			

			foreach my $attachment (@$topLevelAttachments) {
				print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
				handleAttachment(
					$ua,                        $soap,
					$cfg->param("bc.username"), $cfg->param("bc.password"),
					$attachment,                $messagePage->result->{'id'},
					$cfToken
				);

			}
			
			# handle comment attachment

			my $comments = toList( $response, 'comments' );

			foreach my $comment (@$comments) {
				my $attachments = toList( $comment, 'attachments' );
				foreach my $attachment (@$attachments) {
					print
"\t** handling attachment $attachment->{name} of type $attachment->{content_type}\n";
					handleAttachment(
						$ua,
						$soap,
						$cfg->param("bc.username"),
						$cfg->param("bc.password"),
						$attachment,
						$messagePage->result->{'id'},
						$cfToken
					);

				}

			}
			

			$ccontent = "";
		}
		else {
			print "$topic->{'topicable'}->{'type'}\n";
		}
	}
}


#!/opt/local/bin/perl
use REST::Client;
use JSON;
# Data::Dumper makes it easy to see what the JSON returned actually looks like 
# when converted into Perl data structures.
use Data::Dumper;
use MIME::Base64;
use Term::ReadKey;
 
# https://developer.atlassian.com/display/FECRUDEV/Writing+a+REST+Client+in+Perl

sub toList {
   my $data = shift;
   my $key = shift;
   if (ref($data->{$key}) eq 'ARRAY') {
       $data->{$key};
   } elsif (ref($data->{$key}) eq 'HASH') {
       [$data->{$key}];
   } else {
       [];
   }
}
if ($#ARGV ne 2) {
    print "usage: $0 <username> <accountId> <projectId>\n";
    exit 1;
}
my $username = $ARGV[0];
my $accountId = $ARGV[1];
my $projectId = $ARGV[2];
my $password;
# read password
print "Enter your bc password: ";
ReadMode 'noecho';
$password = ReadLine 0;
chomp $password;
ReadMode 'normal';
print "\n";


my $basecampHost = 'https://basecamp.com';
my $baseURL ='/' . $accountId . '/api/v1';
my $headers = {Accept => 'application/json', 'User-Agent' => 'bc2wiki tool (' . $username . ')', => Authorization => 'Basic ' . encode_base64($username . ':' . $password)};
my $client = REST::Client->new();
$client->setHost($basecampHost);
$client->GET(
    $baseURL . '/projects/' . $projectId . '/topics.json', 
    $headers
);
my $response = from_json($client->responseContent());
#my $topics = toList($response->{'reviews'},'reviewData');
foreach $topic (@$response) {
    my $id = $topic->{'id'};
	my $title = $topic->{'title'};
	print "$id : $title\n";
    #$client->GET(
    #    '/fecru/rest-service/reviews-v1/' . $id . '/reviewers/uncompleted', 
    #    $headers
    #);
}
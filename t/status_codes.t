use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use File::Spec::Functions qw( catfile );
use Plack::Test;
use HTTP::Request::Common;

use Plack::Middleware::Mirror ();

my %requests = (
  '/not/here' => [ 404, [ 'Content-type' => 'text/plain' ], [ 'what are you looking for?' ] ],
  '/ok'       => [ 200, [ 'Content-type' => 'text/plain' ], [ 'okee dokee' ] ],
  '/saved'    => [ 379, [ 'Content-type' => 'text/plain' ], [ 'what is this status?' ] ],
);

plan tests => (3 * keys %requests);

my $dir = tempdir( CLEANUP => 1 );

# TODO: test empty arrayref

my $response;
my $app = Plack::Middleware::Mirror->wrap(
  sub { $response },
  path => qr/./,
  mirror_dir => $dir,
  status_codes => [ 379 ], # ignoring 200 (contrived)
  #debug => 1,
);

test_psgi $app, sub {
  my ($cb) = @_;

  while ( my ($path, $fake) = each %requests ) {
    $response = $fake;
    my $res = $cb->(GET "http://localhost$path");

    # basics
    is $res->code, $fake->[0];
    is $res->content, $fake->[2]->[0];

    my $file = catfile($dir, split(/\//, $path));

    if ( $fake->[0] == 379 ) {
      ok(  -e $file, "file '$file' mirrored according to configuration" );
    }
    else {
      ok( !-e $file, "file '$file' does not exist: path not mirrored" );
    }
  }
};

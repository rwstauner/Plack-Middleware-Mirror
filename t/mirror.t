use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use Path::Class 0.24;
use Plack::Test;
use HTTP::Request::Common;

use Plack::Middleware::Mirror ();

my %requests = (
  '/helper' => "rubber\nducky",
  '/monkey/island.txt' => "I want to be\na mighty pirate."
);

plan tests => 4 * keys %requests;

my $dir = tempdir( CLEANUP => 1 );

my $app = Plack::Middleware::Mirror->wrap(
  sub {
    my ($env) = @_;
    #diag explain $env;
    return [ 200, [ 'Content-Type' => 'text/plain' ], [ $requests{ $env->{PATH_INFO} } ] ];
  },
  path => qr/./,
  mirror_dir => $dir,
  #debug => 1,
);

test_psgi $app, sub {
  my ($cb) = @_;

  while ( my ($path, $content) = each %requests ) {
    my $res = $cb->(GET "http://localhost$path");

    # basics
    is $res->code, 200;
    is $res->content, $content;

    #diag explain [`find $dir`];
    my $file = file($dir, split(/\//, $path));
    ok( -e $file, 'file exists' );

    is slurp( $file ), $content, 'file contains "downloaded" content';
  }
};

sub slurp {
  my ($file) = @_;
  open(my $fh, '<', $file)
    or die "Failed to open mirrored '$file'";
  local $/;
  return <$fh>;
}

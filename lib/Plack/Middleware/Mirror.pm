# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;

package Plack::Middleware::Mirror;
# ABSTRACT: Save responses to disk to mirror a site

use parent 'Plack::Middleware';
use Plack::Util;
use Plack::Util::Accessor qw( path mirror_dir debug status_codes );
use HTTP::Date ();

use File::Path ();
use File::Spec ();

sub call {
  my ($self, $env) = @_;

  # if we decide not to save fall through to wrapped app
  return $self->_save_response($env) || $self->app->($env);
}

# is there any sort of logger available?
sub debug_log {
  my ($self, $message) = @_;
  print STDERR ref($self) . " $message\n"
    if $self->debug;
}

sub prepare_app {
  my ($self) = @_;
  $self->status_codes([200])
    unless defined $self->status_codes;
}

sub _save_response {
  my ($self, $env) = @_;

  # this path matching stuff stolen straight from Plack::Middleware::Static
  my $path_match = $self->path or return;
  my $path = $env->{PATH_INFO};

  for ($path) {
    my $matched = 'CODE' eq ref $path_match ? $path_match->($_) : $_ =~ $path_match;
    return unless $matched;
  }

  # TODO: should we use Cwd here?
  my $dir = $self->mirror_dir || 'mirror';

  my $file = File::Spec->catfile($dir, split(/\//, $path));
  my $fdir = File::Spec->catdir( (File::Spec->splitpath($file))[0, 1] ); # dirname()

  my $content = '';

  # fall back to normal request, but intercept response and save it
  return $self->response_cb(
    $self->app->($env),
    sub {
      my ($res) = @_;

      $self->debug_log("preparing to mirror: $path ($file)")
        if $self->debug;
      return unless $self->should_mirror_status($res->[0]);

      # content filter
      return sub {
        my ($chunk) = @_;

        # end of content
        if ( !defined $chunk ) {

          # if writing to the file fails, don't kill the request
          # (we'll try again next time anyway)
          local $@;
          eval {
            File::Path::mkpath($fdir, 0, oct(777)) unless -d $fdir;
            open(my $fh, '>', $file)
              or die "Failed to open '$file': $!";
            binmode($fh);
            print $fh $content
              or die "Failed to write to '$file': $!";
            # explicitly close fh so we can set the mtime below
            close($fh)
              or die "Failed to close '$file': $!";

            # copy mtime to file if available
            if ( my $lm = Plack::Util::header_get($$res[1], 'Last-Modified') ) {
              $lm =~ s/;.*//; # strip off any extra (copied from HTTP::Headers)
              # may return undef which we could pass to utime, but why bother?
              # zero (epoch) may be unlikely but is possible
              if ( defined(my $ts = HTTP::Date::str2time($lm)) ) {
                utime( $ts, $ts, $file );
              }
            }
          };
          warn $@ if $@;
        }
        # if called multiple times, concatenate response
        else {
          $content .= $chunk;
        }
        return $chunk;
      }
    }
  );
}

sub should_mirror_status {
  my ( $self, $res_code, $path ) = @_;
  my $codes = $self->status_codes || [ 200 ];

  # if codes is an empty arrayref don't restrict by code, just allow all
  return 1 if ! @$codes;

  # if status code is one of the accepted codes, return true
  foreach my $code ( @$codes ) {
    return 1 if $res_code == $code;
  }

  # if none of the above is true don't mirror
  $self->debug_log("ignoring unwanted status ($res_code)")
    if $self->debug;
  return 0;
}

1;

=for test_synopsis
my ($config, $match, $dir);

=head1 SYNOPSIS

  # app.psgi
  use Plack::Builder;

  builder {
    # other middleware...

    # save response to disk (beneath $dir) if uri matches
    enable Mirror => path => $match, mirror_dir => $dir;

    # your app...
  };


  # A specific example: Build your own mirror

  # app.psgi
  use Plack::Builder;

  builder {
    # serve the request from the disk if it exists
    enable Static =>
      path => $config->{match_uri},
      root => $config->{mirror_dir},
      pass_through => 1;
    # if it doesn't exist yet, request it and save it
    enable Mirror =>
      path => $config->{match_uri},
      mirror_dir => $config->{mirror_dir};
    Plack::App::Proxy->new( remote => $config->{remote_uri} )->to_app
  };

=head1 DESCRIPTION

  NOTE: This module is in an alpha stage.
  Only the simplest case of static file request has been considered.
  Handling of anything with a QUERY_STRING is currently undefined.
  Suggestions, patches, and pull requests are welcome.

This middleware will save the content of the response
in a tree structure reflecting the URI path info
to create a mirror of the site on disk.

This is different than L<Plack::Middleware::Cache>
which saves the entire response (headers and all)
to speed response time on subsequent and lessen external network usage.

In contrast this middleware saves the static file requested
to the disk preserving the file name and directory structure.
This creates a physical mirror of the site so that you can do other
things with the directory structure if you desire.

This is probably most useful when combined with
L<Plack::Middleware::Static> and
L<Plack::App::Proxy>
to build up a mirror of another site transparently,
downloading only the files you actually request
instead of having to spider the whole site.

However if you have a reason to copy the responses from your own web app
onto disk you're certainly free to do so
(a interesting form of backup perhaps).

C<NOTE>: This middleware does not short-circuit the request
(as L<Plack::Middleware::Cache> does), so if there is no other middleware
to stop the request this module will let the request continue and
save the latest version of the response each time.
This is considered a feature.

=head1 OPTIONS

=head2 path

This specifies the condition used to match the request (C<PATH_INFO>).
It can be either a regular expression
or a callback (code ref) that can match against C<$_> or even modify it
to alter the path of the file that will be saved to disk.

It works just like
L<< the C<path> argument to Plack::Middleware::Static|Plack::Middleware::Static/CONFIGURATIONS >>
since the code was stolen right from there.

=head2 mirror_dir

This is the directory beneath which files will be saved.

=head2 status_codes

This to an array ref of acceptable status codes to mirror.
The default is C<[ 200 ]>
which means that only a normal C<200 OK> response will be saved.

Set this to an empty array ref (C<[]>) to mirror regardless of response code.

=head2 debug

Set this to true to print debugging statements to STDERR.

=for :stopwords TODO

=head1 TODO

=for :list
* Accept callbacks for response/content to determine if it shouled be mirrored
* Determine how this (should) work(s) with non-static resources (query strings)
* Create C<Plack::App::Mirror> to simplify creating simple site mirrors.

=head1 SEE ALSO

=for :list
* L<Plack::Middleware::Cache>
* L<Plack::Middleware::Static>
* L<Plack::App::Proxy>

=cut

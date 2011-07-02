# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;

package Plack::Middleware::Mirror;
# ABSTRACT: Save responses to disk to mirror a site

use parent 'Plack::Middleware';
use Plack::Util;
use Plack::Util::Accessor qw( path mirror_dir debug );

use File::Path ();
use Path::Class 0.24 ();

sub call {
  my ($self, $env) = @_;

  # if we decide not to save fall through to wrapped app
  return $self->_save_response($env) || $self->app->($env);
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

  my $file = Path::Class::File->new($dir, split(/\//, $path));
  my $fdir = $file->parent;
  $file = $file->stringify;

  # FIXME: do we need to append to $response->[2] manually?
  my $content = '';

  # TODO: use logger?
  print STDERR ref($self) . " mirror: $path ($file)\n"
    if $self->debug;

  # fall back to normal request, but intercept response and save it
  return $self->response_cb(
    $self->app->($env),
    sub {
      #my ($response) = @_;
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
            # TODO: utime the file with Last-Modified
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

=for :stopwords TODO

=head1 TODO

=for :list
* C<utime> the mirrored file using Last-Modified
* Tests
* Determine how this (should) work(s) with non-static resources (query strings)
* Create C<Plack::App::Mirror> to simplify creating simple site mirrors.

=head1 SEE ALSO

=for :list
* L<Plack::Middleware::Cache>
* L<Plack::Middleware::Static>
* L<Plack::App::Proxy>

=cut

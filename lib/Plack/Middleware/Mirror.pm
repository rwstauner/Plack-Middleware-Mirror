# vim: set ts=2 sts=2 sw=2 expandtab smarttab:
use strict;
use warnings;

package Plack::Middleware::Mirror;
# ABSTRACT: Save responses to disk to mirror a site

use parent 'Plack::Middleware';
use Plack::Util;
use Plack::Util::Accessor qw(path mirror_dir debug);

use File::Path qw(make_path);;
use File::Basename ();

sub call {
  my ($self, $env) = @_;

  my $matches = $self->path or return;
  $matches = [ $matches ] unless ref $matches eq 'ARRAY';

  # what is the best way to get this value?
  # Plack::Request->new($env)->path;
  my $path_info = $env->{PATH_INFO};

  for my $match (@$matches) {
    return $self->_save_response($env, $path_info)
      if ref($match) eq 'CODE' ? $match->($path_info) : $path_info =~ $match;
  }
  return $self->app->($env);
}

sub _save_response {
  my ($self, $env, $path_info) = @_;
  # TODO: should we use Cwd here?
  my $dir = $self->mirror_dir || 'mirror';

  # TODO: use File::Spec
  my $file = $dir . $path_info;
  # FIXME: do we need to append to $response->[2] manually?
  my $content = '';

  # TODO: use logger?
  print STDERR ref($self) . " mirror: $path_info ($file)\n"
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
          # TODO: there must be something more appropriate than dirname()
          my $fdir = File::Basename::dirname($file);
          make_path($fdir) unless -d $fdir;

          # if writing to the file fails, don't kill the request
          local $@;
          eval {
            open(my $fh, '>', $file)
              or die "Failed to open '$file': $!";
            binmode($fh);
            print $fh $content
              or die "Failed to write to '$file': $!";
            # TODO: utime the file? is that info available?
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

=head1 DESCRIPTION

  NOTE: This is currently considered alpha quality.
  Only the simplest case has been considered.
  Suggestions, patches, and pull requests are welcome.

This middleware will save the content of the response to disk
in a tree structure reflecting the URI path info
to create a mirror of the site on disk.

This is different than L<Plack::Middleware::Cache>
which saves the entire response (headers and all)
to speed response time on subsequent and lessen external network usage.

In contrast this middleware saves the static file requested
to the disk preserving the file name and directory structure.
This creates a physical mirror of the site so that you can do other
things with the directory structure if you desire.

=for :stopwords TODO

=head1 TODO

=for :list
* Tests
* use File::Spec
* Determine how this (should) work(s) with non-static resources (query strings)

=cut

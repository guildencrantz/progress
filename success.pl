#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw ($RealBin);
use local::lib "$RealBin/local";

use Data::Dumper;
use DateTime;
use Digest::MD5 qw(md5_hex);
use Getopt::Long;
use Git::Repository::Log::Iterator;
use Git::Repository;
use LWP::Simple;

my $after;
my $avatar_output_dir = '.avatar';
my $before;
my $no_fetch;
my $no_gravatar;
my $outfile;
my $repo_glob;
my $resolution;
my $target_length_seconds;
my $title;
my @repositories;

GetOptions(
  'a|after=s'      => \$after,
  'b|before=s'     => \$before,
  'd|gravatar_dir' => \$avatar_output_dir,
  'g|glob=s'       => \$repo_glob,
  'l|length=i'     => \$target_length_seconds,
  'no_fetch'       => \$no_fetch,
  'no_gravatar'    => \$no_gravatar,
  'o|outfile'      => \$outfile,
  'resolution=s'   => \$resolution,
  'r|repository=s' => \@repositories,
  'title=s'        => \$title,
);

push(@repositories, glob($repo_glob)) if defined $repo_glob;

my @git_flags;
push(@git_flags, "--after=${after}") if defined $after;
push(@git_flags, "--before=${before}") if defined $before;

$target_length_seconds = 60 if ! defined $target_length_seconds;
$outfile = 'success.mp4';
$resolution = '1024x768' if ! defined $resolution;
$title = defined $title ? "--title '$title'" : '';

my $avatar_size       = 90;

mkdir($avatar_output_dir) unless -d $avatar_output_dir;

my %processed_authors;
my @combined_log;

foreach my $repo_name (@repositories) {
  print "Processing ${repo_name}\n";

  my $repo = Git::Repository->new( git_dir => "/home/mhenkel/src/rp/$repo_name/.git" );
  # TODO: Allow passing the remote_branch on the CLI
  my $remote_branch;
  my $remote_repo;
  foreach ($repo->run('branch', '-vv')) {
    # If the local branch isn't in sync with the remote there's a colon
    # and description of the state difference after the remote branch path
    if(/master\s+\w+\s+\[(([^\/]+?)\/[^\]\:]+).*?\].+/) {
      $remote_branch = $1;
      $remote_repo = $2;
    }
  }
  unless(defined $no_fetch) {
    my $remote_repo;
    defined $remote_repo ? $repo->run('fetch', $remote_repo) : next;
  }

  my $repo_log_iterator = Git::Repository::Log::Iterator->new($repo, $remote_branch, "--name-status", @git_flags);

  while (my $log = $repo_log_iterator->next) {
    unless ($no_gravatar || $processed_authors{$log->author_name}++) {

      my $author_image_file = $avatar_output_dir . '/' . $log->author_name . '.png';
      if (! -e $author_image_file) {
        printf "Checking for gravatar for %s\n", $log->author_name;

        my $grav_url = sprintf(
          'http://www.gravatar.com/avatar/%s?d=404&size=%i',
          md5_hex(lc $log->author_email),
          $avatar_size
        );
        my $rc = getstore($grav_url, $author_image_file);

        sleep(1);

        if($rc != 200) {
          unlink($author_image_file);
        }
      }
    }

    my @files = split /\n/, $log->extra;
    foreach (@files) {
      my ($status, $file) = split /\s+/;
      push @combined_log, sprintf(
        "%s|%s|%s|%s\n",
        $log->author_gmtime,
        $log->author_name,
        $status,
        "${repo_name}/${file}"
      );
    }
  }
}

@combined_log = sort @combined_log;

my $combined_log_path = "/tmp/success_combined_log.$$";
open (COMBINED_LOG, '>', $combined_log_path);
print COMBINED_LOG @combined_log;
close COMBINED_LOG;

my $first_day_with_data = DateTime->from_epoch(epoch => (split /\|/, $combined_log[0])[0]);
my $last_day_with_data = DateTime->from_epoch(epoch => (split /\|/, $combined_log[-1])[0]);
my $actual_days = $first_day_with_data->delta_days($last_day_with_data)->in_units('days');

my $seconds_per_day = $target_length_seconds / $actual_days;

`xvfb-run -a -s "-screen 0 ${resolution}x24" gource ${combined_log_path} --log-format custom --background-image ~/src/success/success.png -s ${seconds_per_day}  -i 0 -${resolution} --highlight-users --highlight-dirs --hide mouse --key --stop-at-end --user-image-dir ${avatar_output_dir} --output-framerate 25 ${title} --output-ppm-stream - | ffmpeg -y -r 25 -f image2pipe -vcodec ppm -i - -vcodec libx264 -preset medium -crf 23 -threads 0 -bf 0 ${outfile}` or die "Unable to generate movie: $!\n";

print "Done.\n";


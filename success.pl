#!/usr/bin/env perl

use strict;
use warnings;

use FindBin;
use local::lib "$FindBin::Bin/local";

use Data::Dumper;
use DateTime;
use Digest::MD5 qw(md5_hex);
use Getopt::Long;
use Git::Repository::Log::Iterator;
use Git::Repository;
use LWP::Simple;

my $repositories;

print Dumper($@);

GetOptions(
  'repository' => \$repositories
);

print "repositories: " . Dumper($repositories);

my $avatar_size       = 90;
my $avatar_output_dir = '.gravatars';
my $outfile = 'gource.mp4';
#my $RESOLUTION = '1024x768';
my $RESOLUTION = '640x480';
my $target_length_seconds = 60;
my $total_days = 14;

mkdir($avatar_output_dir) unless -d $avatar_output_dir;

# TODO: Dynamicize
my $repo_name = 'auth_engine_aggregator';
my $since = '14.days';

my %processed_authors;
my @combined_log;

foreach my $repo_name ($repositories) {
  my $repo = Git::Repository->new( git_dir => "/home/mhenkel/src/rp/$repo_name/.git" );

  my $repo_log_iterator = Git::Repository::Log::Iterator->new($repo, "--name-status", "--since=${since}");

  while (my $log = $repo_log_iterator->next) {
    unless ($processed_authors{$log->author_name}++) {

      my $author_image_file = $avatar_output_dir . '/' . $log->author_name . '.png';
      if (! -e $author_image_file) {
        my $grav_url = sprintf(
          'http://www.gravatar.com/avatar/%s?d=404&size=%i',
          md5_hex(lc $log->author_email),
          $avatar_size
        );
        my $rc = getstore($grav_url, $author_image_file);

        sleep(1);

        if($rc != 200) {
          unlink($author_image_file);
          next;
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

##gource will not close when reading from a pipe like this.
#my $gource_pid = open(GOURCE, "| gource - --log-format custom --background-image ~/src/success/success.png -s ${seconds_per_day}  -i 0 -$RESOLUTION --highlight-users --highlight-dirs --hide mouse --key --stop-at-end --user-image-dir $avatar_output_dir --output-framerate 25 --output-ppm-stream - | ffmpeg -y -r 25 -f image2pipe -vcodec ppm -i - -vcodec libx264 -preset ultrafast -crf 1 -threads 0 -bf 0 $outfile") or die "Unable to open gource: $!\n";
#
#print GOURCE @combined_log;
#print GOURCE "\n";
#
#close GOURCE;

my $combined_log_path = "/tmp/success_combined_log.$$";
open (COMBINED_LOG, '>', $combined_log_path);
print COMBINED_LOG @combined_log;
close COMBINED_LOG;

my $first_day_with_data = DateTime->from_epoch(epoch => (split /\|/, $combined_log[0])[0]);
my $last_day_with_data = DateTime->from_epoch(epoch => (split /\|/, $combined_log[-1])[0]);
my $actual_days = $first_day_with_data->delta_days($last_day_with_data)->days;

my $seconds_per_day = $target_length_seconds / $actual_days;

`gource $combined_log_path --log-format custom --background-image ~/src/success/success.png -s ${seconds_per_day}  -i 0 -$RESOLUTION --highlight-users --highlight-dirs --hide mouse --key --stop-at-end --user-image-dir $avatar_output_dir --output-framerate 25 --output-ppm-stream - | ffmpeg -y -r 25 -f image2pipe -vcodec ppm -i - -vcodec libx264 -preset ultrafast -crf 1 -threads 0 -bf 0 $outfile` or die "Unable to generate movie: $!\n";

print "Done.\n";


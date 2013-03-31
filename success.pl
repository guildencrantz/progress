#!/usr/bin/env perl

use strict;
use warnings;

use DateTime;

use LWP::Simple;
use Digest::MD5 qw(md5_hex);

my $avatar_size       = 90;
my $avatar_output_dir = '.gravatars';
my $outfile = 'gource.mp4';
my $RESOLUTION = '1024x768';
my $target_length_seconds = 60;
my $total_days = 14;
my $seconds_per_day = $target_length_seconds / $total_days;

mkdir($avatar_output_dir) unless -d $avatar_output_dir;

# TODO: Dynamicize
my $repo = 'auth_engine_aggregator';
my $since = '14.days';

my %processed_authors;
my @combined_log;

open(GIT_LOG, "git log --pretty=format:'%at|%ae|%an' --name-status --since ${since} |")
  or die "Failed to read git-log: $!\n";

my $timestamp;
my $email;
my $author;

while (<GIT_LOG>) {
  if (/^$/) {
    undef $timestamp;
    undef $email;
    undef $author;
  } elsif (! defined $timestamp) {
    chomp;
    ($timestamp,$email,$author) = split /\|/;
    next if $processed_authors{$author}++;

    my $author_image_file = $avatar_output_dir . '/' . $author . '.png';
    next if -e $author_image_file;

    my $grav_url = sprintf(
      'http://www.gravatar.com/avatar/%s?d=404&size=%i',
      md5_hex(lc $email),
      $avatar_size
    );
    #warn "fetching image for '$author' $email ($grav_url)...\n";

    my $rc = getstore($grav_url, $author_image_file);

    sleep(1);

    if($rc != 200) {
      unlink($author_image_file);
      next;
    }
  } else {
    chomp;
    my ($status, $file) = split '\s+';
    push @combined_log, sprintf(
      "%s|%s|%s|%s\n",
      $timestamp,
      $author,
      $status,
      "${repo}/${file}"
    );
  }
}

close GIT_LOG;

@combined_log = sort(@combined_log);

my $combined_log_path = '/tmp/gource-team.log';
open(GOURCE_LOG, ">$combined_log_path");
print GOURCE_LOG @combined_log;
close GOURCE_LOG;

`gource $combined_log_path --background-image ~/src/success/success.png -s ${seconds_per_day}  -i 0 -$RESOLUTION --highlight-users --highlight-dirs --hide mouse --key --stop-at-end --user-image-dir $avatar_output_dir --output-framerate 60 --output-ppm-stream - | ffmpeg -y -r 60 -f image2pipe -vcodec ppm -i - -vcodec libx264 -preset ultrafast -crf 1 -threads 0 -bf 0 $outfile`;
unlink($combined_log_path);


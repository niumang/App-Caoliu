use FindBin qw($Bin);
use lib "$Bin/../lib";
use strict;
use warnings;
use File::Basename;
use App::Caoliu;
use Mojo::Log;
use App::Caoliu::Utils 'dumper';
use YAML 'Dump';
use 5.010;

my $c = App::Caoliu->new( category => ['wuma'], target => '/tmp/' );
$c->log->debug( "I want to say " . Dump( $c->category ) );
my @posts = $c->reap;

# if you want to see the image,just download image here
for (@posts) {
    if ( $_->{bt} ) {
        $c->downloader->download_image(
            path => dirname( $_->{bt} ),
            imgs => $_->{preview_imgs}
        );
    }
}
say "all done";


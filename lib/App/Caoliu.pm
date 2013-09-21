package App::Caoliu;

# ABSTRACT: a awsome module,suck greate fire wall!
use Mojo::Base "Mojo";
use Mojo::Home;
use Mojo::UserAgent;
use Mojo::Log;
use Mojo::Util;
use Mojo::URL;
use Mojo::Collection;
use Mojo::IOLoop;
use File::Basename;
use App::Caoliu::Parser;
use App::Caoliu::Downloader;
use App::Caoliu::Utils 'dumper';
no warnings 'deprecated';

use constant FEEDS => {
    WUMA  => 'http://t66y.com/rss.php?fid=2',
    YOUMA => 'http://t66y.com/rss.php?fid=15',
    OUMEI => 'http://t66y.com/rss.php?fid=4',
};
use constant DOWNLOAD_FILE_TIME => 1200;

has timeout      => 60;
has proxy        => '127.0.0.1:8087';
has log          => sub { Mojo::Log->new };
has category     => sub { [qw( wuma youma donghua oumei)] };
has parser       => sub { App::Caoliu::Parser->new };
has index        => 'http://t66y.com';
has home         => sub { Mojo::Home->new };
has downloader   => sub { App::Caoliu::Downloader->new };
has target       => '.';
has loop         => sub { Mojo::IOLoop->delay };
has parallel_num => 20;

my @downloaded_files;

sub new {
    my $self = shift->SUPER::new(@_);

    Carp::croak("category args must be arrayref")
      if ref $self->category ne ref [];
    $self->downloader->ua->http_proxy(
        join( '', 'http://sri:secret@', $self->proxy ) );
    $ENV{LOGGER} = $self->log;

    return $self;
}

sub reap {
    my $self = shift;
    my $category = shift || $self->category;

    return if not scalar @{ $self->category };

    my @download_links;
    my @feeds = map { FEEDS->{ uc $_ } } @{ $self->category };
    $self->log->debug( "show feeds: " . dumper \@feeds );

    # fetch all rmdown_link
    # parallel get post page and download bt files
    $self->_non_blocking_get_torrent(@feeds);
    unless ( Mojo::IOLoop->is_running ) {
        $self->loop->wait;
        $self->log->debug(
            "Downloaded files list:" . dumper [@downloaded_files] );
        return wantarray ? @downloaded_files : scalar(@downloaded_files);
    }
}

sub _non_blocking_get_torrent {
    my ( $self, @feeds ) = @_;

    for my $feed (@feeds) {
        $self->loop->begin;
        $self->downloader->ua->get(
            $feed => sub {
                $self->_process_feed(@_);
            }
        );
    }
}

sub _process_feed {
    my ( $self, $ua, $tx ) = @_;
    my @posts;
    my $processer;

    if ( $tx->success ) {
        my $xml             = $tx->res->body;
        my $post_collection = $self->parser->parse_rss($xml);
        $processer = sub {
            for (@_) {
                $ua->get( $_->{link} => sub { $self->_process_posts(@_) } );
            }
        };

        # to avoid deep recusing warnning ,every turn run 20 tasks
        if ( $post_collection->size > $self->parallel_num ) {
            $processer->( $post_collection->[ 0 .. 20 ] );
            if ( $post_collection->size - 20 ) {
                $processer->(
                    $post_collection->[ 21 .. $post_collection->size ] );
            }
        }
        else {
            $processer->( @{$post_collection} );
        }
    }
}

sub _process_posts {
    my ( $self, $ua, $tx ) = @_;
    my $post_hashref;

    if ( $tx->success ) {
        $post_hashref = $self->parser->parse_post( $tx->res->body );
        $post_hashref->{source} = $tx->req->url->to_string;

        if ( my $download_link = $post_hashref->{rmdown_link} ) {

            # set a alarm clock,when async download,perhaps program will block
            # here,and every thread will block...
            eval {
                local $SIG{ALRM} = sub { die "TIMEOUT" };
                alarm DOWNLOAD_FILE_TIME;
                my $retry_times = 3;
                while ($retry_times) {
                    my $file =
                      $self->downloader->download_torrent( $download_link,
                        $self->target );
                    $post_hashref->{bt} = $file;
                    last if $file;
                    if ( $retry_times == 1 ) {
                        sleep 3;
                    }
                    if ( $retry_times == 2 ) {
                        sleep 1;
                    }
                    $retry_times--;
                }
                alarm 0;
            };
            if ( $@ =~ m/TIMEOUT/ ) {
                $self->log->error( "Download file timeout ..... in "
                      . $post_hashref->{rmdown_link} );
            }
            if ($@) { $self->log->error($@); }
        }
        push @downloaded_files, $post_hashref;
    }
}

1;

=pod

=head1 NAME

=head1 DESCRIPTION

=head1 USAGE 

=cut

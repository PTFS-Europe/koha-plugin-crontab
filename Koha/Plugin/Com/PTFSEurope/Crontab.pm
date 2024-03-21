use utf8;

package Koha::Plugin::Com::PTFSEurope::Crontab;

use Modern::Perl;
use base qw(Koha::Plugins::Base);

use POSIX qw(strftime);
use Module::Metadata;
use Config::Crontab;
use YAML::XS;

use C4::Context;

$YAML::XS::Boolean = "JSON::PP";

#BEGIN {
#    my $path = Module::Metadata->find_module_by_name(__PACKAGE__);
#    $path =~ s!\.pm$!/lib!;
#    unshift @INC, $path;
#
#    use Crontab::API;
#}

our $VERSION  = "{VERSION}";
our $metadata = {
    name            => 'Crontab',
    author          => 'Martin Renvoize',
    description     => 'Script scheduling',
    date_authored   => '2023-04-25',
    date_updated    => "1970-01-01",
    minimum_version => '22.1100000',
    maximum_version => undef,
    version         => $VERSION,
};

sub new {
    my ( $class, $args ) = @_;

    $args->{'metadata'} = $metadata;
    my $self = $class->SUPER::new($args);

    return $self;
}

sub admin {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    my $template = $self->get_template( { file => 'crontab.tt' } );

    my $ct = Config::Crontab->new();
    my $cron_file = C4::Context->config('koha_plugin_crontab_cronfile') || undef;
    $ct->file($cron_file) if $cron_file;
    $ct->mode('block');
    $ct->read or do {
        $template->param( error => $ct->error );
        $self->output_html( $template->output() );
        return;
    };

    my $blocks = [];
    my @environment;
    for my $block ( $ct->blocks ) {

        # Get block parts
        my @comments = $block->select( -type => 'comment' );
        my @env      = $block->select( -type => 'env' );
        my @events   = $block->select( -type => 'event' );

        # Get block id
        my $id_line = shift @comments;

        # Skip first block (plugin header)
        next if ( $id_line->data =~ 'Koha Crontab manager' );

        # Set block id
        my $id;
        if ( $id_line->data =~ /# BLOCKID: (\d+)/ ) {
            $id = $1;
        }
        else {
            $template->param(
                error => "Found block with missing ID: " . $id_line->data );
            $self->output_html( $template->output() );
            return;
        }

        # Global environment block
        unless (@events) {
            push @environment, @comments;
            push @environment, @env;
            next;
        }

        my @comments_stripped;
        for my $comment (@comments) {
            my $stripped = $comment->dump;
            $stripped =~ s/^# //;
            push @comments_stripped, $stripped;
        }

        push @{$blocks},
          {
            id          => $id,
            comments    => \@comments_stripped,
            environment => \@env,
            events      => \@events
          };
    }
    $template->param(
        environment => \@environment,
        blocks      => $blocks
    );
    $self->output_html( $template->output() );
}

sub api_routes {
    my ( $self, $args ) = @_;

    my $spec_str = $self->mbf_read('openapi.yaml');
    my $spec     = Load $spec_str;

    return $spec;
}

sub api_namespace {
    my ($self) = @_;

    return 'crontab';
}

sub install() {
    my ( $self, $args ) = @_;

    my $existing = 1;

    my $ct = Config::Crontab->new();
    my $cron_file = C4::Context->config('koha_plugin_crontab_cronfile') || undef;
    $ct->file($cron_file) if $cron_file;
    $ct->mode('block');
    $ct->read or do {
        $existing = 0;
        warn "No crontab found, installing default";
    };

    my $global_env = 0;
    if ($existing) {

        # Take a backup
        my $path       = $self->mbf_dir . '/backups/';
        my $now_string = strftime "%F_%H-%M-%S", localtime;
        my $filename   = $path . 'install_' . $now_string;
        $ct->write("$filename");

        # Read existing crontab, update it to identify blocks
        # we can manage
        # BLOCKID:
        my $block_id = 0;
        for my $block ( $ct->blocks ) {
            for my $comment (
                $block->select(
                    -type    => 'comment',
                    -data_re => 'Koha Crontab manager'
                )
              )
            {
                return 1;    # Already installed
            }

            if ( $block_id == 0 ) {
                my @env      = $block->select( -type => 'env' );
                my @events   = $block->select( -type => 'event' );
                if ( @env && !@events ) {
                    $global_env = 1;
                    $block->first(
                        Config::Crontab::Comment->new(
                            -data => "# BLOCKID: " . $block_id
                        )
                    );
                }
            } else {
                $block->first(
                    Config::Crontab::Comment->new(
                        -data => "# BLOCKID: " . ++$block_id
                    )
                );
            }
        }
    }

    # Set first block to state we're maintained by the plugin
    my $header_block = Config::Crontab::Block->new();
    $header_block->first(
        Config::Crontab::Comment->new(
            -data =>
"# This crontab file is managed by the Koha Crontab manager plugin"
        )
    );
    $ct->first($header_block);

    # Set some useful global environment if it doesn't already exist
    if ( !$global_env ) {
        my $env_block = Config::Crontab::Block->new();
        my $env_lines;

        push @{$env_lines},
          Config::Crontab::Comment->new( -data => '# BLOCKID: 0' );

        push @{$env_lines},
          Config::Crontab::Env->new(
            -name   => 'PERL5LIB',
            -value  => '/usr/share/koha/lib',
            -active => 1
          );
        push @{$env_lines},
          Config::Crontab::Env->new(
            -name   => 'KOHA_CRON_PATH',
            -value  => '/usr/share/koha/bin/cronjobs',
            -active => 1
          );

        my $instance = C4::Context->config('database');
        $instance =~ s/koha_//;

        push @{$env_lines},
          Config::Crontab::Env->new(
            -name   => 'KOHA_CONF',
            -value  => "/etc/koha/sites/$instance/koha-conf.xml",
            -active => 1
          );

        $env_block->lines($env_lines);

        $ct->after( $header_block, $env_block );
    }

    # Add a hash so we can tell if the managed content has
    # been modified externally and warn the user during updates

    ## write out crontab file
    warn "Writing crontab: " . $ct->dump;
    $ct->write;

    return 1;
}

1;

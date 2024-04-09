use utf8;

package Koha::Plugin::Com::PTFSEurope::Crontab::Controller;

use Modern::Perl;

use C4::Log qw( logaction );

use Koha::Plugin::Com::PTFSEurope::Crontab;

use Mojo::Base 'Mojolicious::Controller';

use POSIX qw(strftime);
use Config::Crontab;

use C4::Context;
use C4::Log;

=head1 API

=head2 Class Methods

=head3 Method to update a cron block

=cut

sub add {
    my $c = shift->openapi->valid_input or return;

    if ( my $r = check_user_allowlist($c) ) { return $r; }

    my $plugin = Koha::Plugin::Com::PTFSEurope::Crontab->new({});
    my $logging = $plugin->retrieve_data('enable_logging') // 1;

    my $ct = Config::Crontab->new();
    my $cron_file = C4::Context->config('koha_plugin_crontab_cronfile') || undef;
    $ct->file($cron_file) if $cron_file;
    $ct->mode('block');
    $ct->read or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not read crontab file: " . $ct->error }
        );
    };

    my $last_block = 0;
    my @id_lines = $ct->select( -type => 'comment', -data_re => "# BLOCKID: " );
    if (@id_lines) {
        $id_lines[-1]->data() =~ /.*(\d+)/;
        $last_block = $1;
    }

    my $next_block = $last_block + 1;
    my $body       = $c->req->json;

    # Construct new block
    my $lines;
    my $newblock = Config::Crontab::Block->new();
    push @{$lines},
      Config::Crontab::Comment->new( -data => "# BLOCKID: $next_block" );

    # Comments
    for my $comment ( @{ $body->{comments} } ) {
        push @{$lines}, Config::Crontab::Comment->new( -data => "# $comment" );
    }

    # Events
    for my $event ( @{ $body->{events} } ) {
        push @{$lines},
          Config::Crontab::Event->new(
            -datetime => $event->{schedule},
            -command  => $event->{command}
          );
    }

    ## TODO: Add Environment handling as needed?

    # Set block lines
    $newblock->lines($lines);

    # Append block
    $ct->last($newblock);

    # Write to crontab
    $ct->write
      or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not write to crontab: " . $ct->error }
        );
      };

    logaction( 'SYSTEMPREFERENCE', 'ADD', $$, "CronTabPlugin | \n" . $ct->dump ) if $logging;

    return $c->render(
        status  => 201,
        openapi => { success => Mojo::JSON->true }
    );
}

sub update {
    my $c = shift->openapi->valid_input or return;

    if ( my $r = check_user_allowlist($c) ) { return $r; }

    my $plugin = Koha::Plugin::Com::PTFSEurope::Crontab->new({});
    my $logging = $plugin->retrieve_data('enable_logging') // 1;

    my $ct = Config::Crontab->new();
    my $cron_file = C4::Context->config('koha_plugin_crontab_cronfile') || undef;
    $ct->file($cron_file) if $cron_file;
    $ct->mode('block');
    $ct->read or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not read crontab file" }
        );
    };

    # Find block
    my $block_id = $c->validation->param('block_id');
    my @id_lines =
      $ct->select( -type => 'comment', -data => "# BLOCKID: $block_id" );
    unless ( scalar @id_lines == 1 ) {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not uniquely identify cronjob block." }
        );
    }

    my $block = $ct->block( $id_lines[0] );
    my $body  = $c->req->json;

    # Construct new block
    my $lines;
    my $newblock = Config::Crontab::Block->new();
    push @{$lines},
      Config::Crontab::Comment->new( -data => "# BLOCKID: $block_id" );

    # Comments
    for my $comment ( @{ $body->{comments} } ) {
        push @{$lines}, Config::Crontab::Comment->new( -data => "# $comment" );
    }

    # Environment
    for my $environment ( @{ $body->{environments} } ) {
        push @{$lines},
          Config::Crontab::Env->new( -data => $environment );
    }

    # Events
    for my $event ( @{ $body->{events} } ) {
        push @{$lines},
          Config::Crontab::Event->new(
            -datetime => $event->{schedule},
            -command  => $event->{command}
          );
    }

    # Set block lines
    $newblock->lines($lines);

    # Replace block
    $ct->replace( $block, $newblock );

    # Write to crontab
    $ct->write
      or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not write to crontab: " . $ct->error }
        );
      };

    logaction( 'SYSTEMPREFERENCE', 'MODIFY', $$, "CronTabPlugin | \n" . $ct->dump ) if $logging;

    return $c->render(
        status  => 200,
        openapi => { success => Mojo::JSON->true }
    );
}

sub delete {
    my $c = shift->openapi->valid_input or return;

    if ( my $r = check_user_allowlist($c) ) { return $r; }

    my $plugin = Koha::Plugin::Com::PTFSEurope::Crontab->new({});
    my $logging = $plugin->retrieve_data('enable_logging') // 1;

    my $ct = Config::Crontab->new();
    my $cron_file = C4::Context->config('koha_plugin_crontab_cronfile') || undef;
    $ct->file($cron_file) if $cron_file;
    $ct->mode('block');
    $ct->read or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not read crontab file" }
        );
    };

    # Find block
    my $block_id = $c->validation->param('block_id');
    my @id_lines =
      $ct->select( -type => 'comment', -data => "# BLOCKID: $block_id" );
    unless ( scalar @id_lines == 1 ) {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not uniquely identify cronjob block." }
        );
    }

    my $block = $ct->block( $id_lines[0] );
    $ct->remove($block) or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not remove block: " . $ct->error }
        );
    };

    # Write to crontab
    $ct->write
      or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not write to crontab: " . $ct->error }
        );
      };

    logaction( 'SYSTEMPREFERENCE', 'DELETE', $$, "CronTabPlugin | \n" . $ct->dump ) if $logging;

    return $c->render(
        status  => 204,
        openapi => { success => Mojo::JSON->true }
    );
}

sub update_environment {
    my $c = shift->openapi->valid_input or return;

    if ( my $r = check_user_allowlist($c) ) { return $r; }

    my $plugin = Koha::Plugin::Com::PTFSEurope::Crontab->new({});
    my $logging = $plugin->retrieve_data('enable_logging') // 1;

    my $ct = Config::Crontab->new();
    my $cron_file = C4::Context->config('koha_plugin_crontab_cronfile') || undef;
    $ct->file($cron_file) if $cron_file;
    $ct->mode('block');
    $ct->read or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not read crontab file" }
        );
    };

    # Environment is special BLOCKID: 0
    my $block_id = 0;
    my @id_lines =
      $ct->select( -type => 'comment', -data => "# BLOCKID: $block_id" );
    unless ( scalar @id_lines == 1 ) {
        return $c->render(
            status  => 500,
            openapi =>
              { error => "Could not uniquely identify environment block." }
        );
    }

    my $block = $ct->block( $id_lines[0] );
    my $body  = $c->req->json;

    # Construct new block
    my $lines;
    my $newblock = Config::Crontab::Block->new();
    push @{$lines},
      Config::Crontab::Comment->new( -data => "# BLOCKID: $block_id" );

    # Comments
    for my $comment ( @{ $body->{comments} } ) {
        push @{$lines}, Config::Crontab::Comment->new( -data => "$comment" );
    }

    # Environment
    for my $environment ( @{ $body->{environments} } ) {
        push @{$lines},
          Config::Crontab::Env->new( -data => "$environment" );
    }

    # Set block lines
    $newblock->lines($lines);

    # Replace block
    $ct->replace( $block, $newblock );

    # Write to crontab
    $ct->write
      or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not write to crontab: " . $ct->error }
        );
      };

    logaction( 'SYSTEMPREFERENCE', 'MODIFY', $$, "CronTabPlugin | \n" . $ct->dump ) if $logging;

    return $c->render(
        status  => 200,
        openapi => { success => Mojo::JSON->true }
    );
}

sub backup {
    my $c = shift->openapi->valid_input or return;

    if ( my $r = check_user_allowlist($c) ) { return $r; }

    my $plugin = Koha::Plugin::Com::PTFSEurope::Crontab->new;

    my $ct = Config::Crontab->new();
    my $cron_file = C4::Context->config('koha_plugin_crontab_cronfile') || undef;
    $ct->file($cron_file) if $cron_file;
    $ct->mode('block');
    $ct->read or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not read crontab file" }
        );
    };

    # Take a backup
    my $path       = $plugin->mbf_dir . '/backups/';
    my $now_string = strftime "%F_%H-%M-%S", localtime;
    my $filename   = $path . 'backup_' . $now_string;
    $ct->write("$filename") or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not write to backup: " . $ct->error }
        );
    };

    return $c->render(
        status  => 200,
        openapi => { filename => "backup_" . $now_string }
    );
}

sub check_user_allowlist {
    my ( $c ) = @_;

    if ( my $koha_plugin_crontab_user_allowlist = C4::Context->config('koha_plugin_crontab_user_allowlist') ) {
        my @borrowernumbers = split(',', $koha_plugin_crontab_user_allowlist );
        my $bn = C4::Context->userenv->{number};
        if ( grep( /^$bn$/, @borrowernumbers ) ) {
            return undef;
        } else {
            return $c->render(
                status  => 401,
                openapi => { error => "You are not authorised to use this plugin" }
            );
        }
    }
}

1;

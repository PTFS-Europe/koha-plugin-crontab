use utf8;

package Koha::Plugin::Com::PTFSEurope::Crontab::Controller;

use Modern::Perl;
use Mojo::Base 'Mojolicious::Controller';

use Config::Crontab;

=head1 API

=head2 Class Methods

=head3 Method to update a cron block

=cut

sub update {
    my $c = shift->openapi->valid_input or return;

    my $ct = new Config::Crontab;
    $ct->mode('block');
    $ct->read or do {
        return $c->render(
            status  => 500,
            openapi => { error => "Could not read crontab file" }
        );
    };

    my $block_id = $c->validation->param('block_id');
    my $block    = Koha::Patrons->find($block_id);

    unless ($block) {
        return $c->render(
            status  => 404,
            openapi => { error => "Patron not found." }
        );
    }

    return $c->render( status => 200,
        openapi => { bothered => Mojo::JSON->true } );
}

1;

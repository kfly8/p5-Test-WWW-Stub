package Test::WWW::Stub;
use 5.008001;
use strict;
use warnings;

our $VERSION = "0.01";

use Carp ();
use Guard;  # guard
use LWP::Protocol::PSGI;
use Plack::Request;
use Test::More ();
use List::MoreUtils ();
use URI;

# PSGI app の場合は第2引数に Plack::Request でラップされたのもついてきます
our $Handlers = { };
our @Requests;

sub register {
    my ($class, $uri_or_re, $app_or_res) = @_;
    $app_or_res //= [200, [], []];
    my $old_handler = $Handlers->{$uri_or_re};

    $Handlers->{$uri_or_re} = {
        type => (ref $uri_or_re || 'Str'),
        (ref $app_or_res eq 'CODE'
            ? ( app => $app_or_res )
                : ( res => $app_or_res )),
    };
    defined wantarray && return guard {
        if ($old_handler) {
            $Handlers->{$uri_or_re} = $old_handler;
        } else {
            delete $Handlers->{$uri_or_re};
        }
    };
}

sub last_request {
    return undef unless @Requests;
    return $Requests[-1];
}

sub requests { @Requests }

sub requested_ok {
    my ($class, $method, $url) = @_;
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    Test::More::ok(
        List::MoreUtils::any(sub {
            my $req_url = $_->uri->clone;
               $req_url->path_query($req_url->path);
            $_->method eq $method && $req_url eq $url
        }, @Requests),
        "stubbed $method $url",
    ) or Test::More::diag Test::More::explain [ map { $_->method . ' ' . $_->uri } @Requests ]
}

my $app = sub {
    my ($env) = @_;
    my $req = Plack::Request->new($env);

    push @Requests, $req;

    # クエリは app で処理してほしい
    my $uri = $req->uri->clone;
       $uri->path_query($uri->path);

    for my $key (keys %$Handlers) {
        my $handler = $Handlers->{$key};
        my @match;
        if ($handler->{type} eq 'Regexp' ? (@match = ($uri =~ qr<$key>)) : $uri eq $key) {
            if (my $app = $handler->{app}) {
                $env->{'test.www.stub.handler'} = [ $key, $app ];
                my $res = $app->($env, $req, @match);
                return $res if $res;
            } elsif (my $res = $handler->{res}) {
                return $res;
            } else {
                Test::More::BAIL_OUT 'Handler MUST be a PSGI app or an ARRAY';
            }
        }
    }

    my $level = $Test::Builder::Level;
    my (undef, $file, $line) = caller($level);
    while ($file && $file !~ m<\.t$>) {
        (undef, $file, $line) = caller(++$level);
    }
    my $method = $req->method;
    Test::More::diag "Unexpected external access: $method $uri at $file line $line";

    return [ 499, [], [] ];
};

LWP::Protocol::PSGI->register($app);

sub unstub {
    Carp::croak 'guard is required' unless defined wantarray;
    LWP::Protocol::PSGI->unregister;
    return guard {
        LWP::Protocol::PSGI->register($app);
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

Test::WWW::Stub - It's new $module

=head1 SYNOPSIS

    use Test::WWW::Stub;

=head1 DESCRIPTION

Test::WWW::Stub is ...

=head1 LICENSE

Copyright (C) Hatena Co., Ltd.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Asato Wakisaka E<lt>asato.wakisaka@gmail.comE<gt>

Original implementation written by suzak.

=cut


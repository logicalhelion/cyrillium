use v5.38;
use Data::Dumper;

use CGI::Fast;
use CGI::Carp qw(croak);

package Cyrillium::App 0.010131 {

    use parent qw(CGI::Application);

    use Class::Tiny qw(
        _matched_route
    ),
    {
        debug => sub { 0 },
    };


    ## CLASS METHODS ##
    # this is an event loop that instatiates an an application
    # object to handle each request.
    sub start_app {
        my $class = shift;
        my %params = @_;

        $class->prep() or die("ERROR:  Failed to prep application.");

        while (my $q = CGI::Fast->new() ) {
            my $app = $class->new({QUERY => $q });
            $app->run();
        }
        1;
    }

    sub prep {
        my $class = shift;
        my %params = @_;

        # install callbacks for init and load_tmpl phase
        # $class->app_callback('init','cyrillium_init');
        # $class->app_callback('load_tmpl','cyrillium_load_tmpl'); 
        #print STDERR "ROUTES TO PREP:\n", Dumper($class->ROUTES);

        if ( defined $class->ROUTES  ) {
            #print STDERR "REGISTERING _path_info_routing CALLBACK\n"; 
            $class->add_callback('prerun','_prerun_path_info_routing');
        }

        # add PSGI-like postrun output handling
        if ( defined $class->ARRAYREF_RESPONSES && $class->ARRAYREF_RESPONSES > 0 ) {
            $class->add_callback('postrun','_postrun_response');
        }

        return 1;
    }

    # define the primitives apps will redefine later
    sub RUN_MODES { undef }
    sub DEFAULT_MODE { 'http_404_not_found' }
    sub ERROR_HANDLER { 'error_response' }
    sub ROUTES { undef }
    sub ARRAYREF_RESPONSES { 1 }

    ## OBJECT METHODS ##

    ## CGI::Application METHODS ##

    # override setup() method
    # to set up app obj from framework
    sub setup {
        my $self = shift;

        # set some defaults
        my $runmodes   = $self->RUN_MODES   // ['http_404_not_found','error_response'];
        my $start_mode = $self->DEFAULT_MODE;
        my $error_mode = $self->ERROR_HANDLER;

        # pull all the routes' run_modes and add them to the run_modes() list
        my @route_run_modes;
        if (defined $self->ROUTES) {
            my %run_mode_hash;
            my @route_info = values %{ $self->ROUTES };
            for my $route (@route_info) {
                my @run_modes = values %$route;
                for (@run_modes) {
                    $run_mode_hash{$_} = 1;
                }
            }
            # make sure start and error modes are in the run modes array
            $run_mode_hash{$start_mode} = 1;
            $run_mode_hash{$error_mode} = 1;
            @route_run_modes = keys %run_mode_hash;
            $runmodes = \@route_run_modes;
        }

        #FIXME:test
        print STDERR "RUN_MODES: ",Dumper($runmodes),"\n" if $self->debug;
        print STDERR "START MODE: ",$start_mode,"\n" if $self->debug;
        print STDERR "ERROR MODE: ",$error_mode,"\n" if $self->debug;

        $self->mode_param(1);  # this won't be used if ROUTES is defined
        $self->run_modes( $runmodes );
        $self->start_mode( $start_mode );
        $self->error_mode( $error_mode );
    }

    ## CALLBACKS ##

    ##
    # _prerun_path_info_routing()
    # routes request based on path_info
    sub _prerun_path_info_routing {
        my $self   = shift;
        my $routes = $self->ROUTES;
        my $q      = $self->query;
        my $path_info      = $q->path_info;
        my $request_method = $q->request_method;
        my $run_mode;

        if ( defined $routes && defined $path_info) {
            # ok we have routes, compare the routes to path_info
            # and see if we can route the request somewhere
            print STDERR "EVALUATING ROUTES\n" if $self->debug; #FIXME:t 
            my @pi = split(/\//, $path_info);
            print STDERR "PATH_INFO PARTS: ", join(','=>@pi),"\n" if $self->debug;
            foreach my $route (sort keys %$routes) {
                print STDERR "ROUTE: ", $route if $self->debug;
                my @r = split(/\//, $route);
                say "ROUTE PARTS: ", join(','=>@r) if $self->debug;
                # first see if the parts counts match
                if (scalar @pi != scalar @r) {
                    # the path_info parts count doesn't match this route
                    # go to the next route
                    next;
                }
                # now check each part of the route to see if it matches path_info
                # for *reasons*, initially assume the route will match
                my $matched = 1;
                for(my $i = 1; $i < @r; $i++) {
                    # is this a path anchor, or a path variable?
                    if ( $r[$i] =~ /^\:/) {
                        # this is a variable; make sure path_info has...some value
                        if (defined $pi[$i] && $pi[$i] ) {
                            next;
                        }
                        else {
                            # for this route to match, path_info has to have a value here
                            $matched = 0;
                            last;
                        }
                    }
                    else {
                        # this is an anchor; make sure path_info matches 
                        if ( $r[$i] eq $pi[$i] ) {
                            # it matches this part!  proceed to the next part
                            next;
                        }
                        else {
                            # it does NOT match, give up on this route
                            $matched = 0;
                            last;
                        }
                    }
                }

                # ok, if this route matched, is the HTTP method valid for this route?
                if ($matched) {
                    print STDERR "ROUTE MATCHED: ",$route,"\n" if $self->debug;
                    foreach my $method (keys %{ $routes->{$route} }){
                        if ($method eq $request_method) {
                            # OK, we have a match on route & HTTP method
                            # set the run mode and we're done!
                            $self->_matched_route($route);
                            $run_mode = $routes->{$route}->{$method};
                            last;
                        }
                    }
                }
                # if we have a run mode, we can stop searching for a matching route
                last if $run_mode;
            }
            # we've run through all the routes
            # we either have a run_mode to set
            # or we're issuing a 404 Not Found because no routes matched
            # #FIXME:or keep track of route match/method mismatch so we can do a 405?
            if (defined $run_mode) {
                $self->prerun_mode($run_mode);
            }
            # we couldn't find a route, so we'll default to the start mode
            # default start mode will respond with a 404
        }
        # if we don't have any ROUTES or any path_info,
        # we don't do *anything at all*
    }


    sub _postrun_response {
        my $self = shift;
        my $response = shift;

        # if the response data points to a scalar,
        # then the current run mode is doesn't need JSON
        # conversion; just pass on thru
        return 1 if ref($response) eq 'SCALAR';

        # is the response an arrayref?
        my $r = $$response;
        if (ref($r) && ref($r) eq 'ARRAY') {
            # the first element is the status
            my $s = $r->[0];
            $self->header_add('-status' => $s);
            # the second element is the headers
            my %h = @{ $r->[1] };
            # then set headers
            for (sort keys %h) {
                $self->header_add($_ =>  $h{$_} );
            }

            # is the response body a scalar or array?
            # if scalar, return it
            # if array, join together and return it
            my $b = '';
            if ( ref($r->[2]) && ref($r->[2]) eq 'ARRAY') {
                $b = join(' ' =>  @{$r->[2]} ); 
            }
            else {
                $b = $r->[2];
            }
            $$response = $b;
        } # response wasn't a SCALAR or ARRAY?  I guess we don't do anything
    }


    ## HELPER METHODS ##

    sub params_from_path_info {
        my $self = shift;
        my $q = $self->query;
        my @r = split(/\//, $self->_matched_route);
        my @p = split(/\//, $q->path_info);
        my %params;

        for(my $i = 0; $i < @r; $i++) {
            if ($r[$i] =~ /^:/) {
                my @n = split(/:/, $r[$i]);
                $params{$n[1]} =  $p[$i];
            }
        }
        return %params;
    }

    ## DEFAULT RUN_MODES ##

    ##
    # error_response
    # Default error handler
    # this was pulled from the LW2F project
    # and updated for Cyrillium to take an arrayref instead
    # of a hashref.  
    sub error_response {
        my $self = shift;
        my $E = @_ ? shift : '';
        if ( ref($E) ) {
            $self->header_add(-status => $E->[0]);
            $self->header_add(-type => 'text/plain');
            return $E->[1];
        }
        else {
            $self->header_add(-status => '500 Internal Server Error');
            $self->header_add(-type => 'text/plain');
            return "$E";
        }
    }

    ##
    # http_404_not_found
    # default run mode 
    # if path info routing doesn't find a route,
    # this will return a 404 Not Found error
    sub http_404_not_found {
        return [
            '404 Not Found',
            [
                -type => 'text/html; charset=utf-8',
            ],
            qq{
<!doctype html>
<html lang="en">
    <head><title>Not Found</title></head>
<body>
    <h1>Not Found</h1>
</body>
</html>
            }
        ];
    }
}
1;
__END__

=head1 AUTHOR

Logical Helion, LLC L<https://www.logicalhelion.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2025 by Logical Helion, LLC.

This library is free software; you can redistribute it and/or modify
it under the terms of the Apache License 2.0.
=cut

#!/usr/bin/perl

use lib qw(. ../lib);
use HelloWorld;

##
# set socket/perms/listen queue using CGI::Fast
$ENV{FCGI_SOCKET_PATH} = "localhost:8888";
$ENV{FCGI_LISTEN_QUEUE} = 50;

HelloWorld->start_app();


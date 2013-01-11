#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

use FindBin qw();
use lib $FindBin::Bin.'/../testlib';

use Test03;
Test03->new_with_command->run;
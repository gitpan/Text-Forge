# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..4\n"; }
END { print "not ok 1\n" unless $loaded; }
use Text::Forge;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):
                                                
sub ok     { print "ok $test\n"; $test++ }
sub not_ok { print "not ok $test\n"; $test++ }

$^W = 0;
$test = 2;
my $forge = new Text::Forge;

# set a header in the outer scope -- this should persist through all tests
$forge->header( author => 'maurice' );

# TEST 2
my $doc = $forge->generate('templates/scope1.tf');
$doc->as_string eq "Author: maurice\n\nBODY\n" ? ok : not_ok;

# TEST 3
# This template sets a header, which should disappear outside the sub
$doc = $forge->generate('templates/scope2.tf');
$doc->as_string eq "Author: maurice\nLinux: rocks\n\nBODY\n" ? ok : not_ok;

# TEST 4 (TEST 2 again to see if above header is present) 
$doc = $forge->generate('templates/scope1.tf');
$doc->as_string eq "Author: maurice\n\nBODY\n" ? ok : not_ok;      

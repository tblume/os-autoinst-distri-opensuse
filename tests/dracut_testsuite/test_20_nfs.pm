# SUSE's openQA tests
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Run upstream test TEST-20-NFS after applying SUSE patches.
# Maintainer: dracut maintainers <dracut-maintainers@suse.de>

use base "dracut_testsuite_test";
use warnings;
use strict;
use testapi;

my $test_name = 'TEST-20-NFS';
my $logs_dir = '/tmp/dracut-testsuite-logs';
my $timeout = get_var('DRACUT_TEST_DEFAULT_TIMEOUT') || 300;

sub run {
    my ($self) = @_;
    select_console 'root-console';
    
    assert_script_run "mkdir -p $logs_dir";
    assert_script_run "cd /usr/lib/dracut/test/$test_name";
    assert_script_run "export basedir=/usr/lib/dracut && export testdir=/usr/lib/dracut/test/ && ./test.sh --setup 2>&1 | tee $logs_dir/$test_name-setup.log", $timeout;
    assert_script_run "export basedir=/usr/lib/dracut && export testdir=/usr/lib/dracut/test/ && ./test.sh --run 2>&1 | tee $logs_dir/$test_name-run.log", $timeout;
    
    # Clean
    assert_script_run "cd /usr/lib/dracut/test/$test_name";
    assert_script_run './test.sh --clean';
}

sub test_flags {
    return {always_rollback => 1};
}
sub post_fail_hook {
    my ($self) = shift;
    $self->SUPER::post_fail_hook;
    assert_script_run("tar -czf dracut-testsuite-logs.tar.gz $logs_dir", 600);
    upload_logs('dracut-testsuite-logs.tar.gz');
}

1;

# SUSE's openQA tests
#
# Copyright 2019-2020 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Run test executed by TEST-07-PID1 from upstream after openSUSE/SUSE patches.
# Maintainer: Thomas Blume <tblume@suse.com>

use base 'systemd_testsuite_test';
use warnings;
use strict;
use testapi;

sub pre_run_hook {
    my ($self) = @_;
    #prepare test
    $self->testsuiteprepare('TEST-07-PID1');
}

sub run {
    #run test
    my $timeout = get_var('SYSTEMD_TEST_DEFAULT_TIMEOUT') || 600;
    assert_script_run 'cd /usr/lib/systemd/tests/integration-tests';
    assert_script_run 'export NO_BUILD=1 && make -C TEST-07-PID1 run 2>&1 | tee /tmp/testsuite.log', $timeout;
    assert_script_run 'grep "TEST-07-PID1 RUN: .* \[OK\]" /tmp/testsuite.log';
}

sub test_flags {
    return {always_rollback => 1};
}


1;

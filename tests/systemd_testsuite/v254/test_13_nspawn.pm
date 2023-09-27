# SUSE's openQA tests
#
# Copyright 2019-2020 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Run test executed by TEST-13-NSPAWN from upstream after openSUSE/SUSE patches.
# Maintainer: Sergio Lindo Mansilla <slindomansilla@suse.com>, Thomas Blume <tblume@suse.com>

use base 'systemd_testsuite_test';
use warnings;
use strict;
use testapi;

sub pre_run_hook {
    my ($self) = @_;
    #prepare test
    $self->testsuiteprepare('TEST-13-NSPAWN');
}

sub run {
    #run test
    my $timeout = 900;
    assert_script_run 'cd /usr/lib/systemd/tests/integration-tests';
    assert_script_run 'export NO_BUILD=1 && make -C TEST-13-NSPAWN run 2>&1 | tee /tmp/testsuite.log', $timeout;
    assert_script_run 'grep "TEST-13-NSPAWN RUN: .* \[OK\]" /tmp/testsuite.log';
}

sub test_flags {
    return {always_rollback => 1};
}


1;

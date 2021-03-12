# SUSE's openQA tests
# #
# # Copyright © 2019 SUSE LLC
# #
# # Copying and distribution of this file, with or without modification,
# # are permitted in any medium without royalty provided the copyright
# # notice and this notice are preserved.  This file is offered as-is,
# # without any warranty.
#
# # Summary: library functions for setting up the tests and uploading logs in error case.
# # Maintainer: Thomas Blume <tblume@suse.com>
#
#
package sap_library_test;
use base "opensusebasetest";

use strict;
use warnings;
use known_bugs;
use testapi;
use power_action_utils 'power_action';
use utils 'zypper_call';
use version_utils qw(is_opensuse is_sle is_tumbleweed);
use bootloader_setup qw(change_grub_config grub_mkconfig);

sub testpackageinstall {
    my ($self) = @_;
    my $qatest_repo = get_var('QA_TEST_REPO', '');
    if (!$qatest_repo) {
        if (is_opensuse()) {
            my $sub_project;
            if (is_tumbleweed()) {
                $sub_project = 'Tumbleweed/openSUSE_Tumbleweed/';
            }
            else {
                (my $version, my $service_pack) = split('\.', get_required_var('VERSION'));
                $sub_project = "Leap:/$version/openSUSE_Leap_$version.$service_pack/";
            }
            $qatest_repo = 'https://download.opensuse.org/repositories/devel:/openSUSE:/QA:/' . $sub_project;
        }
        else {
            my $version_with_service_pack = get_required_var('VERSION');
            $qatest_repo = "http://download.suse.de/ibs/QA:/Head/SLE-$version_with_service_pack/";
        }
        die '$qatest_repo is not set' unless ($qatest_repo);
    }

    select_console 'root-console';

    # install systemd testsuite
    zypper_call "ar $qatest_repo SAP-systemdlib-testrepo";
    zypper_call '--gpg-auto-import-keys ref';
    zypper_call 'in SAP-systemdlib-tests';
}

sub run {
    my ($self) = @_;
    $self->testpackageinstall;
    assert_script_run('cd /usr/lib/systemd/test/SAP/');
    assert_script_run('./prepare_for_systemd.sh');
    assert_script_run "su - abcadm -c '/usr/lib/systemd/test/SAP/systemd_test.sh'";
}

sub post_fail_hook {
    my ($self) = @_;
    #upload logs from given testname
    $self->tar_and_upload_log('/usr/lib/systemd/tests/logs',       '/tmp/SAP-systemdlib-tests-logs.tar.bz2');
    $self->tar_and_upload_log('/var/log/journal /run/log/journal', 'binary-journal-log.tar.bz2');
    $self->save_and_upload_log('journalctl --no-pager -axb -o short-precise', 'journal.txt');
}


1;

# SUSE's openQA tests
#
# Copyright 2019 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: library functions for setting up the tests and uploading logs in error case.
# Maintainer: Thomas Blume <tblume@suse.com>


package systemd_testsuite_test;
use base "opensusebasetest";

use strict;
use warnings;
use known_bugs;
use testapi;
use Utils::Backends;
use Utils::Architectures;
use power_action_utils 'power_action';
use utils 'zypper_call';
use version_utils qw(is_opensuse is_sle is_tumbleweed);
use bootloader_setup qw(change_grub_config grub_mkconfig);
use Utils::Logging qw(save_and_upload_log tar_and_upload_log);

sub testsuiteinstall {
    my ($self) = @_;
    my $unsigned = '';
    my $gpgparm ='--gpg-auto-import-keys';
    if (get_var('ALLOW_UNSIGNED')) {
        $unsigned = '--gpgcheck-allow-unsigned' ;
        $gpgparm = '--no-gpg-checks';
    }

    # The isotovideo setting QA_TESTSUITE_REPO is not mandatory.
    # QA_TESTSUITE_REPO is meant to override the default repos with a custom OBS repo to test changes on the test suite package.
    my $qa_testsuite_repo = get_var('QA_TESTSUITE_REPO', '');
    if (!$qa_testsuite_repo) {
        if (is_opensuse()) {
            my $sub_project;
            if (is_tumbleweed()) {
                $sub_project = 'Tumbleweed/openSUSE_Tumbleweed/';
            } else {
                (my $version, my $service_pack) = split('\.', get_required_var('VERSION'));
                $sub_project = "Leap:/$version/openSUSE_Leap_$version.$service_pack/";
            }
            $qa_testsuite_repo = 'https://download.opensuse.org/repositories/devel:/openSUSE:/QA:/' . $sub_project;
        }
        else {
            my $version_with_service_pack = get_required_var('VERSION');
            $qa_testsuite_repo = "http://download.suse.de/ibs/QA:/Head/SLE-$version_with_service_pack/";
        }
        die '$qa_testsuite_repo is not set' unless ($qa_testsuite_repo);
    }

    select_console 'root-console';

    if (is_sle('15+') && !main_common::is_updates_tests) {
        # add devel tools repo for SLE15 to install strace
        my $devel_repo = get_required_var('REPO_SLE_MODULE_DEVELOPMENT_TOOLS');
        zypper_call "ar -c $utils::OPENQA_FTP_URL/" . $devel_repo . " devel-repo";
    }

    my $addonpkgs;
    if (is_tumbleweed()) {
        my $addon_repo1 = "https://download.opensuse.org/repositories/server:/monitoring/openSUSE_Tumbleweed";
        zypper_call "ar $unsigned $addon_repo1 addon-repo1";
        zypper_call "$gpgparm ref";

        $addonpkgs = "selinux-policy-devel erofs-utils knot stress";

    } else {
        $addonpkgs = "";
    }

    zypper_call "in strace mtools bzip2 $addonpkgs";

    # install systemd testsuite
    zypper_call "ar $unsigned $qa_testsuite_repo systemd-testrepo";
    zypper_call "$gpgparm ref";
    # use systemd from the repo of the qa package
    if (get_var('SYSTEMD_FROM_TESTREPO')) {
	my $systemd_version = get_var("SYSTEMD_FROM_TESTREPO");
	if ($systemd_version eq '1') {
            $systemd_version = "";
        } else {
            $systemd_version = "=$systemd_version";
    }
        zypper_call "in -f --from systemd-testrepo systemd$systemd_version systemd-sysvinit$systemd_version udev$systemd_version libsystemd0$systemd_version systemd-coredump$systemd_version libudev1$systemd_version";
        change_grub_config('=.*', '=9', 'GRUB_TIMEOUT');
        grub_mkconfig;
        wait_screen_change { enter_cmd "shutdown -r now" };
        if (is_s390x) {
            $self->wait_boot(bootloader_time => 180);
        } else {
            $self->handle_uefi_boot_disk_workaround if (is_aarch64);
            wait_still_screen 10;
            send_key 'ret';
            wait_serial('Welcome to', 300) || die "System did not boot in 300 seconds.";
        }
        if (check_var('DESKTOP', 'textmode')) {
            assert_screen('linux-login', 30);
        } else{
	    $self->wait_boot_past_bootloader;
        }
        reset_consoles;
        select_console('root-console', await_console => 120);
    }
    zypper_call 'in -f -y --from systemd-testrepo systemd-testsuite$systemd_version';

    assert_script_run "rpm -qi systemd";
}

sub testsuiteprepare {
    my $self = shift;
    my ($testname, $option) = @_;

    #cleanup and prepare next test
    assert_script_run "find / -maxdepth 1 -type f -print0 | xargs -0 /bin/rm -f";
    assert_script_run 'find /etc/systemd/system/ -name "schedule.conf" -prune -o \( \! -name *~ -type f -print0 \) | xargs -0 /bin/rm -f';
    assert_script_run "find /etc/systemd/system/ -name 'end.service' -delete";
    assert_script_run "rm -rf /var/tmp/systemd-test*";
    assert_script_run "cd /usr/lib/systemd/tests/integration-tests";
    assert_script_run "export NO_BUILD=1 &&  make -C $testname clean 2>&1 | tee /tmp/testsuite.log", 300;
    assert_script_run 'sed -i \'/install_suse_systemd()/,$s/\[ ! -L "$file" \] \&\& \[ -d "$file" \]/\[ ! -L "$f" \] \&\& \[ -d "$f" \]/\' test-functions';
        if ($testname eq 'TEST-58-REPART') {
            assert_script_run 'sed -i \'/verity.crt/s#ln -s#ln -sf#\' ../testdata/units/testsuite-58.sh';
            assert_script_run "sed -i \'/mksquashfs/s#sbin#usr/bin#\' $testname/test.sh";
    }
    #increase testsuite unit start timeout on slow machines
    #if ($testname eq 'TEST-73-LOCALE') {
    #    assert_script_run "sed -i \'s/ExecStartPre=/TimeoutStartSec=600\\nExecStartPre=/\' ../testdata/units/testsuite-73.service";
    #}

    assert_script_run "export NO_BUILD=1 &&  make -C $testname setup 2>&1 | tee /tmp/testsuite.log", 300;

    if ($option eq 'nspawn') {
        my $testservicepath = script_output "sed -n '/testservice=/s/root/nspawn-root/p' /tmp/testsuite.log";
        assert_script_run "ls -l \$\{testservicepath#testservice=\}";
    }
    else {
        #tests and versions that don't need a reboot
        return if ($testname eq 'TEST-18-FAILUREACTION' || $testname eq 'TEST-21-SYSUSERS' || is_sle('>15-SP2') || is_tumbleweed);

        assert_script_run 'ls -l /etc/systemd/system/testsuite.service';
        #virtual machines do a vm reset instead of reboot
        if (!is_qemu || ($option eq 'needreboot')) {
            wait_screen_change { enter_cmd "shutdown -r now" };
            if (is_s390x) {
                $self->wait_boot(bootloader_time => 180);
            }
            else {
                $self->handle_uefi_boot_disk_workaround if (is_aarch64);
                wait_serial('Welcome to', 300) || die "System did not boot in 300 seconds.";
            }
            wait_still_screen 10;
            assert_screen('linux-login', 30);
            reset_consoles;
            select_console('root-console');
        }
    }

    script_run "clear";
}

sub post_fail_hook {
    my ($self) = @_;
    #upload logs from given testname
    tar_and_upload_log('/tmp/testsuite.log', '/tmp/systemd_testsuite-logs.tar.bz2');
    tar_and_upload_log('/var/log/journal /run/log/journal', 'binary-journal-log.tar.bz2');
    save_and_upload_log('journalctl --no-pager -axb -o short-precise', 'journal.txt');
    upload_logs('/shutdown-log.txt', failok => 1);
}


1;

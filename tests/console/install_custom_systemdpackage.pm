# SUSE's openQA tests
#
# Copyright 2019 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: library functions for setting up the tests and uploading logs in error case.
# Maintainer: Thomas Blume <tblume@suse.com>


package install_custom_systemdpackage;
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

sub run {
    my ($self) = @_;
    # The isotovideo setting SYSTEMD_REPO is not mandatory.
    # SYSTEMD_REPO is meant to override the default repos with a custom OBS repo to test changes on the test suite package.
    my $systemd_repo = get_var('SYSTEMD_REPO');

    if ($systemd_repo) {
        zypper_call "ar $systemd_repo systemd-testrepo";
        zypper_call '--gpg-auto-import-keys ref';
        zypper_call 'in --from systemd-testrepo systemd systemd-sysvinit udev libsystemd0 systemd-coredump libudev1';
        change_grub_config('=.*', '=9', 'GRUB_TIMEOUT');
        grub_mkconfig;
        wait_screen_change { enter_cmd "shutdown -r now" };
        if (is_s390x) {
            $self->wait_boot(bootloader_time => 180);
        } else {
            $self->handle_uefi_boot_disk_workaround if (is_aarch64);
            wait_still_screen 10;
            send_key 'ret';
            wait_serial('localhost login:', 300) || die "System did not boot in 300 seconds.";
        }
        select_console 'root-console';
        enter_cmd "root";
        wait_still_screen 1;
        enter_cmd "$testapi::password";
        wait_still_screen 1;
    } else {
        return 0;
    }
}

sub post_fail_hook {
    my ($self) = @_;
    #upload logs from given testname
    tar_and_upload_log('/var/log/journal /run/log/journal', 'binary-journal-log.tar.bz2');
    save_and_upload_log('journalctl --no-pager -axb -o short-precise', 'journal.txt');
    upload_logs('/shutdown-log.txt', failok => 1);
}


1;

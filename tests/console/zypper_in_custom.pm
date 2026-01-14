# SUSE's openQA tests
#
# Copyright 2009-2013 Bernhard M. Wiedemann
# Copyright 2012-2018 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Package: zypper
# Summary: Add module to install custom packages for testing
# Maintainer: Thomas Blume <Thomas.Blume@suse.com>

use base "consoletest";
use strict;
use warnings;
use testapi;
use utils 'zypper_call';
use version_utils qw(is_transactional);
use transactional;
use serial_terminal 'select_serial_terminal';

sub run {
    select_console 'root-console';

    my $custom_testrepo = get_var('PATCH_TEST_REPO', '');
    my $custom_packages = get_var('PACKAGES', '');
    if ($custom_packages) {
        if (is_transactional) {
            enter_trup_shell;
        }

        zypper_call "ar $custom_testrepo testrepo";
        zypper_call '--gpg-auto-import-keys ref';
        zypper_call "in --from testrepo $custom_packages";

        #add debug logging
        #enter_cmd "mkdir /etc/systemd/system/systemd-logind.service.d/";
        #assert_script_run("echo -e '[Service]\nEnvironment=SYSTEMD_LOG_LEVEL=debug' > /etc/systemd/system/systemd-logind.service.d/override.conf");

        if (is_transactional) {
            exit_trup_shell;
        }
    }

    #reboot routine
    enter_cmd "/usr/bin/sdbootutil set-timeout 5";
    wait_screen_change { enter_cmd "shutdown -r now" };
    wait_still_screen 10;
    send_key 'ret';
    wait_serial('susetest login:', 300) || die "System did not boot in 300 seconds.";
    select_console 'root-console';
    enter_cmd "root";
    wait_still_screen 1;
    enter_cmd "$testapi::password";
    wait_still_screen 1;

    #enable remote ssh access
    enter_cmd "systemctl start sshd";
    enter_cmd "firewall-cmd --add-service ssh";
    enter_cmd "systemctl --no-pager cat systemd-logind";

    #make enabling permanent just in case it reboots later
    enter_cmd "systemctl enable sshd";
    enter_cmd "firewall-cmd --permanent --add-service ssh";

    #prepare for next test
    reset_consoles;
    select_serial_terminal;
}

1;

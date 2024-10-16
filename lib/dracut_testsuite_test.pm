# SUSE's openQA tests
#
# Copyright 2022 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: library functions for setting up the tests and uploading logs in case of error.
# Maintainer: dracut maintainers <dracut-maintainers@suse.de>

package dracut_testsuite_test;
use warnings;
use strict;
use testapi;
use Utils::Architectures qw(is_aarch64);
use Utils::Architectures 'is_s390x';
use bootloader_setup qw(change_grub_config grub_mkconfig);
use base "consoletest";
use utils 'zypper_call';
use power_action_utils 'power_action';
use transactional;
use microos 'microos_reboot';
use version_utils qw(is_sle_micro is_transactional is_leap_micro is_opensuse is_sle is_tumbleweed);

my $logs_dir = '/root/dracut-testsuite-logs';

sub testsuiteinstall {
    my ($self) = @_;
    my $dracut_testsuite_repo = get_var('DRACUT_TESTSUITE_REPO', '');

    select_console 'root-console';

    my $from_repo = '';
    if ($dracut_testsuite_repo) {
        zypper_call "ar $dracut_testsuite_repo dracut-testrepo";
        $from_repo = "--from dracut-testrepo";
    }

    if (is_sle('=15-SP3')) {
        zypper_call "ar https://updates.suse.de/download/SUSE/Backports/SLE-15-SP3_x86_64/standard/?ssl_verify=no devel-repo";
        zypper_call "ar https://updates.suse.de/download/SUSE/Products/SLE-Module-Desktop-Applications/15-SP4/x86_64/product/?ssl_verify=no desktop-repo";
    }

    if (is_sle('=15-SP4')) {
        zypper_call "ar http://dist.suse.de/install/SLP/SLE-15-SP4-Module-Basesystem-LATEST/x86_64/DVD1/ base-repo";
        zypper_call "ar http://dist.suse.de/install/SLP/SLE-15-SP4-Module-Server-Applications-LATEST/x86_64/DVD1/ server-repo";
        zypper_call "ar http://dist.suse.de/install/SLP/SLE-15-SP4-Module-Development-Tools-LATEST/x86_64/DVD1/ devel-repo";
        zypper_call "ar http://dist.suse.de/install/SLP/SLE-15-SP4-Module-Desktop-Applications-LATEST/x86_64/DVD1/ desktop-repo";
        zypper_call "ar https://download.suse.de/ibs/SUSE:/SLE-15:/Update/standard/?ssl_verify=no nbd-repo";
    }

    if (is_sle_micro) {
    #openqa repos have been deleted
        zypper_call "mr -d SLE-Micro-5.3-Pool";
        zypper_call "mr -d SLE-Micro-5.3-Updates";
        script_run('suseconnect -r INTERNAL-USE-ONLY-dd97-133d -e thomas.blume@suse.com');
    }

    #repos necessary for test 16 (dmsquash) -> not yet implemented
    #    zypper_call "ar https://download.suse.de/ibs/SUSE:/SLE-15-SP1:/Update/standard/?ssl_verify=no kiwi-repo";
    #    zypper_call "ar https://download.opensuse.org/repositories/Virtualization:/Appliances:/Builder/openSUSE_Leap_15.4/?ssl_verify=no kiwi-repo";
    #    zypper_call "ar https://download.opensuse.org/repositories/devel:/languages:/python:/backports/15.4/?ssl_verify=no kiwi-overlay-repo";
  
    zypper_call "--gpg-auto-import-keys ref";

    if (check_var('DISTRI', 'sle-micro')) {
        trup_shell 'zypper --gpg-auto-import-keys ref';
        trup_shell 'zypper --non-interactive in dracut-kiwi-overlay python3-kiwi git tree dracut-kiwi-live NetworkManager nfs-kernel-server dhcp-server dhcp-client tcpdump open-iscsi iscsiuio tgt pciutils sysvinit-tools nbd';
        # use dracut from the repo of the qa package
        if ($from_repo) {
            if (is_tumbleweed) {
                trup_shell "zypper --non-interactive in --force $from_repo dracut dracut-qa-testsuite dracut-extra";
            } else {
                trup_shell "zypper --non-interactive in --force $from_repo dracut dracut-mkinitrd-deprecated dracut-qa-testsuite";
            }
	} else {
            trup_shell 'zypper --non-interactive in dracut-qa-testsuite';
        }
    } else {
        zypper_call "--gpg-auto-import-keys ref";
        zypper_call 'in dracut-kiwi-overlay python3-kiwi git tree dracut-kiwi-live NetworkManager nfs-kernel-server dhcp-server dhcp-client tcpdump open-iscsi iscsiuio tgt nbd dash qemu dbus-1-daemon python313-pefile';
        # linuxx64.efi.stub for TEST-12-UEFI
        zypper_call "in --no-recommends systemd-boot systemd-experimental";
        # use dracut from the repo of the qa package
        if ($from_repo) {
            if (is_tumbleweed) {
                zypper_call "in --force $from_repo dracut dracut-qa-testsuite dracut-extra";
            } else {
                zypper_call "in --force $from_repo dracut dracut-mkinitrd-deprecated dracut-qa-testsuite";
            }

	} else {
            zypper_call "in dracut-qa-testsuite";
        }

	change_grub_config('=.*', '=9', 'GRUB_TIMEOUT');
        grub_mkconfig;
        wait_screen_change { enter_cmd "shutdown -r now" };
        if (is_s390x) {
            $self->wait_boot(bootloader_time => 180);
        } else {
            $self->handle_uefi_boot_disk_workaround if (is_aarch64);
            wait_still_screen 10;
            wait_serial('Welcome to', 300) || die "System did not boot in 300 seconds.";
        }
    }

    if (!check_var('DESKTOP', 'textmode')) {
        assert_screen("displaymanager", 500);
        send_key "ctrl-alt-f1";
    }

       #    if (!check_var('DISTRI', 'sle-micro')) {
    assert_screen('linux-login', 30);
    reset_consoles;
    select_console('root-console');
       #    }
}

sub testsuiterun {
    my ($self, $test_name, $option) = @_;
    my $timeout = get_var('DRACUT_TEST_DEFAULT_TIMEOUT') || 300;

    select_console 'root-console';
    if (check_var('DISTRI', 'sle-micro')) {
        assert_script_run "cp -avr /usr/lib/dracut/test /tmp";
        assert_script_run "mount -o bind /tmp/test /usr/lib/dracut/test";
    }
    assert_script_run "mkdir -p $logs_dir";

    if (check_var('DISTRI', 'sle-micro')) {
        assert_script_run "cp -avr /usr/lib/dracut/test /tmp";
        assert_script_run "mount -o bind /tmp/test /usr/lib/dracut/test";
    }
    assert_script_run "cd /usr/lib/dracut/test/$test_name";

    my $NMPREFIX;

    if (substr($test_name, -3, 3) eq "-NM")
    {
        my @test_data = split /-/, $test_name;
        @test_data[1] = '*';
        my $test_name_no_numb = join '-', @test_data;
        $NMPREFIX = substr($test_name_no_numb, 0, -3);
    }

    # Check dracut generation errors
    assert_script_run "! grep -e ERROR -e FAIL $logs_dir/$test_name-setup.log";

    if (check_var('DISTRI', 'sle-micro')) {
        microos_reboot 1;
    }
    else
    {
        power_action('reboot', textmode => 1);
        wait_still_screen(10, 60);
        if (!check_var('DESKTOP', 'textmode')) {
            assert_screen( "displaymanager", 500);
            send_key "ctrl-alt-f1";
        }

    }

    assert_screen('linux-login', 30);
    select_console 'root-console';

    if (defined($NMPREFIX))
    {
        assert_script_run "cd /usr/lib/dracut/test/$NMPREFIX";
        assert_script_run "export basedir=/usr/lib/dracut && export testdir=/usr/lib/dracut/test/ && export NM=1 && ./test.sh --setup 2>&1 > $logs_dir/$test_name-setup.log", $timeout;
        assert_script_run "export basedir=/usr/lib/dracut && export testdir=/usr/lib/dracut/test/ && export NM=1 && ./test.sh --run 2>&1 > $logs_dir/$test_name-run.log", $timeout;
    }
    else
    {
        assert_script_run "cd /usr/lib/dracut/test/$test_name";
        assert_script_run "export basedir=/usr/lib/dracut && export testdir=/usr/lib/dracut/test/ && ./test.sh --setup 2>&1 > $logs_dir/$test_name-setup.log", $timeout;
        assert_script_run "export basedir=/usr/lib/dracut && export testdir=/usr/lib/dracut/test/ && ./test.sh --run 2>&1 > $logs_dir/$test_name-run.log", $timeout;
    }

    # Check dracut generation errors
    assert_script_run "! grep -e ERROR -e FAIL $logs_dir/$test_name-setup.log";
    power_action('reboot', textmode => 1);
    wait_still_screen(10, 60);
    assert_screen("linux-login", 600);
    if (!check_var('DESKTOP', 'textmode')) {
        assert_screen("displaymanager", 500);
        send_key "ctrl-alt-f1";
    }

    if (check_var('DISTRI', 'sle-micro')) {
        microos_reboot 1;
    }
    else
    {
        power_action('reboot', textmode => 1);
        wait_still_screen(10, 60);
        if (!check_var('DESKTOP', 'textmode')) {
            assert_screen( "displaymanager", 500);
            send_key "ctrl-alt-f1";
        }

        assert_screen('linux-login', 30);
        enter_cmd "root";
        wait_still_screen 3;
        type_password;
        wait_still_screen 3;
        send_key 'ret';
    }

    # Clean
    assert_script_run "cd /usr/lib/dracut/test/$test_name";

    if (defined($NMPREFIX))
    {
        assert_script_run "cd /usr/lib/dracut/test/$NMPREFIX";
    }
    assert_script_run 'export basedir=/usr/lib/dracut && export testdir=/usr/lib/dracut/test/ && ./test.sh --clean';
}

sub post_fail_hook {
    my ($self) = shift;
    #$self->SUPER::post_fail_hook;
    assert_script_run("tar -czf dracut-testsuite-logs.tar.gz $logs_dir", 600);
    upload_logs('dracut-testsuite-logs.tar.gz');
}

sub test_flags {
    return {always_rollback => 1};
}

1;

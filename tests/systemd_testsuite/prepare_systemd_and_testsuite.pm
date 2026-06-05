# SUSE's openQA tests
#
# Copyright 2020 SUSE LLC
# SPDX-License-Identifier: FSFAP

# Summary: Prepare systemd and testsuite.
#
# This module works as a 'loader' for the actual systemd-testsuite testcases.
# - install package systemd-testsuite, that contains a patched version of https://github.com/systemd/systemd
# - for each test in the upstream testsuite, filter out those mentioned in the variable SYSTEMD_EXCLUDE
# - for all other, schedule a new openQA testmodule: i.e. loadtest(runner.pm) passing a different name every time
# - when this module ends, the single tests of the systemd testsuite are being executed by openQA as independent test modules.
#
# Maintainer: qe-core@suse.com, Thomas Blume <tblume@suse.com>

use Mojo::Base 'systemd_testsuite_test';
use testapi;
use serial_terminal 'select_serial_terminal';
use utils;
use registration qw(add_suseconnect_product get_addon_fullname is_phub_ready);
use Utils::Backends;
use Utils::Architectures;
use power_action_utils 'power_action';
use version_utils qw(is_opensuse is_sle is_tumbleweed);
use bootloader_setup qw(change_grub_config grub_mkconfig);

sub run {
    my ($self) = @_;    
    my $test_opts = {
        NO_BUILD => get_var('SYSTEMD_NO_BUILD', 1),
        TEST_PREFER_NSPAWN => get_var('SYSTEMD_NSPAWN', 1),
        UNIFIED_CGROUP_HIERARCHY => get_var('SYSTEMD_UNIFIED_CGROUP', 'yes')
    };
    my @pkgs = qw(
      lz4
      busybox
      qemu
      dhcp-client
      python3
      plymouth
      binutils
      netcat-openbsd
      cryptsetup
      less
      device-mapper
      strace
      e2fsprogs
      hostname
      net-tools-deprecated
      git
      distribution-gpg-keys
      coreutils
      ca-certificates-suse
    );
    my $testsrepo = get_var('SYSTEMD_TESTS_REPO');

    select_console('root-console');
    # Package requires PackageHub is available
    return if (!is_phub_ready() && is_sle('<16'));

    zypper_call("ar http://dist.nue.suse.com/ibs/SUSE:/CA/openSUSE_Tumbleweed/ SUSE_CA");
    zypper_call("--gpg-auto-import-keys ref", 180);
    zypper_call("in @pkgs");

    if (get_var('SYSTEMD_FROM_TESTREPO')) {
        zypper_call("ar $testsrepo systemd-tests");
        zypper_call("--gpg-auto-import-keys ref", 180);
        zypper_call 'in --from systemd-tests libsystemd0 libudev1 systemd systemd-lang udev';
            
        change_grub_config('GRUB_TIMEOUT=.*', 'GRUB_TIMEOUT=9', 'GRUB_TIMEOUT');
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
        assert_screen('linux-login', 30);
        reset_consoles;
        select_console('root-console');
    }

    my $sversion = script_output "rpm -q systemd | sed -rn 's/systemd-([0-9]*).*/\\1/p'";
    if ($sversion < 257) {
        if (is_sle("<16")) {
            add_suseconnect_product(get_addon_fullname('legacy'));
            add_suseconnect_product(get_addon_fullname('desktop'));
            add_suseconnect_product(get_addon_fullname('sdk'));
            add_suseconnect_product(get_addon_fullname('phub'));
            add_suseconnect_product(get_addon_fullname('python3'));
            zypper_call("ar 'http://download.suse.de/download/ibs/SUSE:/SLE-%s:/GA/standard/' testsuiterepo");
            zypper_call("--gpg-auto-import-keys ref", 180);
        }

        zypper_call 'in systemd-testsuite';
        
        assert_script_run("cd /usr/lib/systemd/tests/integration-tests/");
    } else {
        my $gitlabtoken = get_var('GITLAB_TOKEN');

        assert_script_run("cd /root");
        assert_script_run("curl -JLO --header \"PRIVATE-TOKEN: $gitlabtoken\" --url 'https://gitlab.suse.de/api/v4/projects/4603/repository/files/run_systemd_testsuite.sh/raw?ref=master'");
        assert_script_run('chmod u+x run_systemd_testsuite.sh');
        assert_script_run("bash -c \"./run_systemd_testsuite.sh --repo $testsrepo setup\" >setup.txt", timeout => 1200);
    }

    # extract all available test cases
    assert_script_run("cd /root/tests/integration-tests/");
    my @schedule = ();
    my $exclude = get_var('SYSTEMD_EXCLUDE');

    if (my $include = get_var('SYSTEMD_INCLUDE')) {
        @schedule = split(',', $include);
    } else {
        my @tests = split(/\n/, script_output(qq(find . -maxdepth 1 -type d -name "TEST-*")));
        foreach my $test (@tests) {
            # trim folder prefix
            $test =~ s/\.\///;
            if (defined($exclude) && $test =~ m/$exclude/) {
                next;
            }
            if ($test eq "TEST-64-UDEV-STORAGE") {
                my @subtests = split(/\n/, script_output(qq(sed -n '/udev_storage_tests/{n;s/.*name. : .\\([a-z]*_[a-z]*_*[a-z]*_*[a-z]*_*[a-z]*\\).*/\\1/p;}' $test/meson.build)));
                foreach my $subtest (@subtests) {
                    push @schedule, "$test-$subtest";
                }
            } elsif ($test eq "TEST-85-NETWORK") {
                my @subtests = split(/\n/, script_output(qq(sed -n '/foreach/,/integration_tests/s/^ *.\\([a-Z]*\\)Tests.*/\\1Tests/gp' $test/meson.build)));
                foreach my $subtest (@subtests) {
                    push @schedule, "$test-$subtest";
                }
            } else {
                push @schedule, $test;
            }
        }
    }

    script_run("cd /root");
    my $testdir = script_output('pwd');

    # execute generic openQA's systemd runner for each test case directory found within the *systemd-tests* package
    # test case options are passed to each scheduled module separately
    foreach my $test (@schedule) {
       # if (($test eq "TEST-07-PID1") || ($test eq "TEST-64-UDEV-STORAGE-simultaneous_events")) {
         my $args = OpenQA::Test::RunArgs->new(test => $test, dir => $testdir, make_opts => $test_opts);
         autotest::loadtest('tests/systemd_testsuite/runner.pm', name => $test, run_args => $args);
       # }
    }

    autotest::loadtest("tests/shutdown/shutdown.pm");
}

sub test_flags {
    return {milestone => 1, fatal => 1};
}

1;

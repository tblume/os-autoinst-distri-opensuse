# Summary: install, remove and update some packages for checking
# the systemd-update-helper functionality, e.g.:
# unit enabling on package install, disabling on package removal,
# reloading on package update.
# Also cover udev reload when new udev rules get installed

use base 'consoletest';
use testapi;
use utils;
use version_utils qw(is_sle is_opensuse is_tumbleweed);
use Mojo::JSON qw(encode_json);
use strict;
use warnings;
use Utils::Logging qw(save_and_upload_log tar_and_upload_log);


sub check_package_install {
    my $testpackages = get_var('TESTPACKAGES', 'open-iscsi');

    #install previous version of open-iscsi
    my $historyversion = script_output("curl -s http://download.opensuse.org/history/latest");

    zypper_call "ar -c http://download.opensuse.org/history/$historyversion/tumbleweed/repo/oss prevrepo";
    zypper_call '--gpg-auto-import-keys ref';
    zypper_call "in --from prevrepo $testpackages";

    #check if daemon gets enabled according to preset
    assert_script_run('curl -L -k https://gitlab.suse.de/tsaupe/openqa-systemd/-/raw/1011b2127255980c2f19df481badb2318e0c6be6/check-presets.sh -o /var/tmp/check-presets.sh');
    script_run('chmod 0755 /var/tmp/check-presets.sh');
    assert_script_run("/var/tmp/check-presets.sh $testpackages");

    #check if udev gets reloaded
}


sub check_package_update {
#1. check systemd daemon-reload

# check with package name change (subpackage see bsc1245551)
#  systemd-update-helper: fix regression introduced when support for package
#  renaming/splitting was added (bsc#1245551)
#  The cleanup of the flags in /run/systemd/rpm was previously handled in the
#  %pretrans/%posttrans sections of the systemd main package. However, this
#  method was ineffective if systemd was not part of the transaction. The cleanup
#  is now run in %transfiletriggerin instead.

zypper_call '--gpg-auto-import-keys ref';
zypper_call 'dup';

#2. check if custom service activation settings, different from preset, persist after an update

}

sub check_package_removal {
#check if all units from the package get stopped and removed
#check if udev gets reloaded

zypper_call 'rm open-iscsi';
}



sub run {
    my ($self) = @_;

    select_console 'root-console';
    $self->check_package_install;
    $self->check_package_update;
    $self->check_package_removal;
}

sub post_fail_hook {
    my ($self) = @_;
    #upload logs from given testname
    tar_and_upload_log('/var/log/journal /run/log/journal', 'binary-journal-log.tar.bz2');
    $self->upload_systemdlib_tests_logs;
}

1;

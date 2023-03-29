# Copyright SUSE LLC
# SPDX-License-Identifier: GPL-2.0-or-later

# Summary: Deploy SAP Landscape using qe-sap-deployment and network peering with Trento server
# Maintainer: QE-SAP <qe-sap@suse.de>, Michele Pagot <michele.pagot@suse.com>

use strict;
use warnings;
use Mojo::Base 'publiccloud::basetest';
use testapi;
use qesapdeployment 'qesap_upload_logs';
use base 'trento';

sub run {
    my ($self) = @_;
    $self->select_serial_terminal;

    my $wd = '/root/work_dir';
    enter_cmd "mkdir $wd";
    my $cmd = '/root/test/trento-server-api-key.sh' .
      ' -u admin' .
      ' -p ' . $self->get_trento_password() .
      ' -i ' . $self->get_trento_ip() .
      " -d $wd";
    my $agent_api_key = script_output($cmd);

    $cmd = $self->install_agent($wd, '/root/test', $agent_api_key, '10.0.0.4');
}

sub post_fail_hook {
    my ($self) = shift;
    $self->select_serial_terminal;
    qesap_upload_logs();
    if (!get_var('TRENTO_EXT_DEPLOY_IP')) {
        trento::k8s_logs(qw(web runner));
        $self->az_delete_group;
    }
    $self->destroy_qesap();
    $self->SUPER::post_fail_hook;
}

1;

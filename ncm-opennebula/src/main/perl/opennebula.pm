# ${license-info}
# ${developer-info}
# ${author-info}

package NCM::Component::opennebula;

use strict;
use warnings;
use version;
use NCM::Component;
use base qw(NCM::Component NCM::Component::OpenNebula::commands);
use vars qw(@ISA $EC);
use LC::Exception;
use CAF::TextRender;
use CAF::Service;
use Net::OpenNebula 0.300.0;
use Data::Dumper;
use Readonly;


Readonly::Scalar my $CEPHSECRETFILE => "/var/lib/one/templates/secret/secret_ceph.xml";
Readonly::Scalar our $ONED_CONF_FILE => "/etc/one/oned.conf";
Readonly::Scalar our $SUNSTONE_CONF_FILE => "/etc/one/sunstone-server.conf";
Readonly::Scalar our $KVMRC_CONF_FILE => "/var/lib/one/remotes/vmm/kvm/kvmrc";
Readonly::Scalar our $ONEADMIN_AUTH_FILE => "/var/lib/one/.one/one_auth";
Readonly::Scalar our $SERVERADMIN_AUTH_DIR => "/var/lib/one/.one/";
Readonly::Array our @SERVERADMIN_AUTH_FILE => qw(sunstone_auth oneflow_auth
                                                 onegate_auth occi_auth ec2_auth);
Readonly::Scalar my $MINIMAL_ONE_VERSION => version->new("4.8.0");
Readonly::Scalar our $ONEADMINUSR => (getpwnam("oneadmin"))[2];
Readonly::Scalar our $ONEADMINGRP => (getpwnam("oneadmin"))[3];

our $EC=LC::Exception::Context->new->will_store_all;

# Set OpenNebula RPC endpoint info
# to connect to ONE API
sub make_one 
{
    my ($self, $rpc) = @_;

    if (! $rpc->{password} ) {
        $self->error("No RPC ONE password set!");
        return;
    }

    $self->verbose("Connecting to host $rpc->{host}:$rpc->{port} as user $rpc->{user} (with password) $ONEADMINUSR");

    my $one = Net::OpenNebula->new(
        url      => "http://$rpc->{host}:$rpc->{port}/RPC2",
        user     => $rpc->{user},
        password => $rpc->{password},
        log => $self,
        fail_on_rpc_fail => 0,
    );
    return $one;
}

# Detect and process ONE templates
sub process_template
{
    my ($self, $config, $type_name, $secret) = @_;
    
    my $type_rel = "$type_name.tt";
    my $tpl = CAF::TextRender->new(
        $type_name,
        { $type_name => $config },
        relpath => 'opennebula',
        log => $secret ? undef : $self,
        );
    if (!$tpl) {
        $self->error("TT processing of $type_rel failed: $tpl->{fail}");
        return;
    }
    return $tpl;
}

# Create/update ONE resources
# based on resource type
sub create_or_update_something
{
    my ($self, $one, $type, $data, %protected) = @_;
    
    my $template = $self->process_template($data, $type);
    my ($name, $new);
    if (!$template) {
        $self->error("No template data found for $type.");
        return;
    }
    if ($template =~ m/^NAME\s+=\s+(?:"|')(.*?)(?:"|')\s*$/m) {
        $name = $1;
        $self->verbose("Found template NAME: $name within $type resource.");
    } else {
        $self->error("Template NAME tag not found within $type resource: $template");
        return;
    }
    if (exists($protected{$name})) {
        $self->info("This resource $type is protected and can not be created/updated: $name");
        return;
    }
    my $cmethod = "create_$type";

    my $used = $self->detect_used_resource($one, $type, $name);
    if (!$used) {
        $self->info("Creating new $name $type resource.");
        $new = $one->$cmethod("$template");
    } elsif ($used == -1) {
        # resource is already there and we can modify it
        $new = $self->update_something($one, $type, $name, "$template");
    }
    return $new;
}


# Removes ONE resources
sub remove_something
{
    my ($self, $one, $type, $resources, %protected) = @_;
    my $method = "get_${type}s";
    my @existres = $one->$method();
    my @namelist = $self->create_resource_names_list($one, $type, $resources);
    my %rnames = map { $_ => 1 } @namelist;

    foreach my $oldresource (@existres) {
        # Remove the resource only if the QUATTOR flag is set
        my $quattor = $self->check_quattor_tag($oldresource);
        if (exists($protected{$oldresource->name})) {
            $self->info("This resource $type is protected and can not be removed: ", $oldresource->name);
        } elsif ($quattor and !$oldresource->used() and !exists($rnames{$oldresource->name})) {
            $self->info("Removing old $type resource: ", $oldresource->name);
            my $id = $oldresource->delete();
            if (!$id) {
                $self->error("Unable to remove old $type resource: ", $oldresource->name);
            }
        } else {
            $self->warn("QUATTOR flag not found or the resource is still used. ",
                        "We can't remove this $type resource: ", $oldresource->name);
        };
    }
    return;
}

# Updates ONE resource templates
sub update_something
{
    my ($self, $one, $type, $name, $template) = @_;
    my $method = "get_${type}s";
    my $update;
    my @existres = $one->$method(qr{^$name$});
    foreach my $t (@existres) {
        # $merge=1, we don't replace, just merge the new templ
        $self->info("Updating old $type Quattor resource with a new template: ", $name);
        $self->debug(1, "New $name template : $template");
        $update = $t->update($template, 1);
    }
    return $update;
}

# Detects if the resource
# is already there and if quattor flag is present
# return undef: resource not used yet
# return 1: resource already used without Quattor flag
# return -1: resource already used with Quattor flag set
sub detect_used_resource
{
    my ($self, $one, $type, $name) = @_;
    my $quattor;
    my $gmethod = "get_${type}s";
    my @existres = $one->$gmethod(qr{^$name$});
    if (@existres) {
        $quattor = $self->check_quattor_tag($existres[0]);
        if (!$quattor) {
            $self->verbose("Name: $name is already used by a $type resource. ",
                        "The Quattor flag is not set. ",
                        "We can't modify this resource.");
            return 1;
        } elsif ($quattor == 1) {
            $self->verbose("Name : $name is already used by a $type resource. ",
                        "Quattor flag is set. ",
                        "We can modify and update this resource.");
            return -1;
        }
    } else {
        $self->verbose("Name: $name is not used by $type resource yet.");
        return;
    }
}

sub detect_ceph_datastores
{
    my ($self, $one) = @_;
    my @datastores = $one->get_datastores();
    
    foreach my $datastore (@datastores) {
        if ($datastore->{data}->{TM_MAD}->[0] eq "ceph") {
            $self->verbose("Detected Ceph datastore: ", $datastore->name);
            return 1;
        }
    }
    $self->info("No Ceph datastores available at this moment.");
    return;
}

sub create_resource_names_list
{
    my ($self, $one, $type, $resources) = @_;
    my ($name, @namelist, $template);

    foreach my $newresource (@$resources) {
        $template = $self->process_template($newresource, $type);
        if ($template =~ m/^NAME\s+=\s+(?:"|')(.*?)(?:"|')\s*$/m) {
            $name = $1;
            push(@namelist, $name);
        }
    }
    return @namelist;
}

sub check_quattor_tag
{
    my ($self, $resource, $user) = @_;

    if ($user and $resource->{data}->{TEMPLATE}->[0]->{QUATTOR}->[0]) {
        return 1;
    }
    elsif (!$user and $resource->{extended_data}->{TEMPLATE}->[0]->{QUATTOR}->[0]) {
        return 1;
    } else {
        return;
    }
}

# This function configures Ceph client
# It sets ceph key in each hypervisor.
sub enable_ceph_node
{
    my ($self, $type, $host, $datastores) = @_;
    my ($secret, $uuid);
    foreach my $ceph (@$datastores) {
        if (defined($ceph->{tm_mad}) && $ceph->{tm_mad} eq 'ceph') {
            if ($ceph->{ceph_user_key}) {
                $self->verbose("Found Ceph user key.");
                $secret = $ceph->{ceph_user_key};
            } else {
                $self->error("Ceph user key not found within Quattor template.");
                return;
            }
            $uuid = $self->set_ceph_secret($type, $host, $ceph);
            return if !$uuid;
            return if !$self->set_ceph_keys($host, $uuid, $secret);
        }
    }
    return 1;
}

# Sets Ceph secret
# to be used by libvirt
sub set_ceph_secret
{
    my ($self, $type, $host, $ceph) = @_;
    my $uuid;
    # Add ceph keys as root
    my $cmd = ['secret-define', '--file', $CEPHSECRETFILE];
    my $output = $self->run_virsh_as_oneadmin_with_ssh($cmd, $host);
    if ($output and $output =~ m/^[Ss]ecret\s+(.*?)\s+created$/m) {
        $uuid = $1;
        if ($uuid eq $ceph->{ceph_secret}) {
            $self->verbose("Found Ceph uuid: $uuid to be used by $type host $host.");
        } else {
            $self->error("UUIDs set from datastore and CEPHSECRETFILE $CEPHSECRETFILE do not match.");
            return;
        }
    } else {
        $self->error("Required Ceph UUID not found for $type host $host.");
        return;
    }
    return $uuid;
}

# Sets Ceph keys
# to be used by libvirt
sub set_ceph_keys
{
    my ($self, $host, $uuid, $secret) = @_;

    my $cmd = ['secret-set-value', '--secret', $uuid, '--base64', $secret];
    my $output = $self->run_virsh_as_oneadmin_with_ssh($cmd, $host, 1);
    if ($output =~ m/^[sS]ecret\s+value\s+set$/m) {
        $self->info("New Ceph key include into libvirt list: ", $output);
    } else {
        $self->error("Error running virsh secret-set-value command: ", $output);
        return;
    }
    return $output;
}

# Execute ssh commands required by ONE
# configure ceph client if necessary
sub enable_node
{
    my ($self, $one, $type, $host, $resources) = @_;
    my ($output, $cmd, $uuid, $secret);
    # Check if we are using Ceph datastores
    if ($self->detect_ceph_datastores($one)) {
        return $self->enable_ceph_node($type, $host, $resources->{datastores});
    }
    return 1;
}

# By default OpenNebula sets a random pass
# for internal users. This function sets the
# new passwords
sub change_opennebula_passwd
{
    my ($self, $user, $passwd) = @_;
    my ($output, $cmd);

    if ($user eq "serveradmin") {
        $cmd = [$user, join(' ', '--driver server_cipher', $passwd)];
    } else {
        $cmd = [$user, $passwd];
    };
    $output = $self->run_oneuser_as_oneadmin_with_ssh($cmd, "localhost", 1);
    if (!$output) {
        $self->error("Quattor unable to modify current $user passwd.");
        return;
    } else {
        $self->info("$user passwd was set correctly.");
    }
    $self->set_one_auth_file($user, $passwd);
    return 1;
}

# Sync hyps VMMs scripts
sub sync_opennebula_hyps
{
    my ($self) = @_;
    my $output;

    $output = $self->run_onehost_as_oneadmin_with_ssh("localhost", 0);
    if (!$output) {
        $self->error("Quattor unable to execute onehost sync command as oneadmin.");
    } else {
        $self->info("OpenNebula hypervisors were synchronized correctly.");
    }
}
# Restart one service
# after any conf change
sub restart_opennebula_service {
    my ($self, $service) = @_;
    my $srv;
    if ($service eq "oned") {
        $srv = CAF::Service->new(['opennebula'], log => $self);
    } elsif ($service eq "sunstone") {
        $srv = CAF::Service->new(['opennebula-sunstone'], log => $self);
    } elsif ($service eq "kvmrc") {
        $self->info("Updated $service file. onehost sync is required.");
        $self->sync_opennebula_hyps();
    }
    $srv->restart() if defined($srv);
}

# Remove/add ONE resources
# based on resource type
sub manage_something
{
    my ($self, $one, $type, $resources, $untouchables) = @_;
    my %protected = map { $_ => 1 } @$untouchables;
    if (!$resources) {
        $self->error("No $type resources found.");
        return;
    } else {
        $self->verbose("Managing $type resources.");
    }

    if (($type eq "kvm") or ($type eq "xen")) {
        $self->manage_hosts($one, $type, $resources, %protected);
        return;
    } elsif ($type eq "user") {
        $self->manage_users($one, $resources, %protected);
        return;
    }

    $self->verbose("Check to remove ${type}s");
    $self->remove_something($one, $type, $resources, %protected);

    if (@$resources) {
        $self->info("Creating new ${type}/s: ", scalar @$resources);
    }
    foreach my $newresource (@$resources) {
        my $new = $self->create_or_update_something($one, $type, $newresource, %protected);
    }
}

# Function to add/remove Xen or KVM hyp hosts
sub manage_hosts
{
    my ($self, $one, $type, $resources, %protected) = @_;
    my ($new, $vnm_mad);
    my $hosts = $resources->{hosts};
    my @existhost = $one->get_hosts();
    my %newhosts = map { $_ => 1 } @$hosts;
    my (@rmhosts, @failedhost);

    if (exists($resources->{host_ovs}) and $resources->{host_ovs}) {
        if ($type eq "kvm") {
            $vnm_mad = "ovswitch";
        } elsif ($type eq "xen") {
            $vnm_mad = "ovswitch_brcompat";
        }
    } else {
        $vnm_mad = "dummy";
    }

    foreach my $t (@existhost) {
        # Remove the host only if there are no VMs running on it
        if (exists($protected{$t->name})) {
            $self->info("This resource $type is protected and can not be removed: ", $t->name);
        } elsif (exists($newhosts{$t->name})) {
            $self->debug(1, "We can't remove this $type host. Is required by Quattor: ", $t->name);
        } elsif ($t->used()) {
            $self->debug(1, "We can't remove this $type host. There are still running VMs: ", $t->name);
        } else {
            push(@rmhosts, $t->name);
            $t->delete();
        }
    }

    if (@rmhosts) {
        $self->info("Removed $type hosts: ", join(',', @rmhosts));
    }

    foreach my $host (@$hosts) {
        my %host_options = (
            'name'    => $host, 
            'im_mad'  => $type, 
            'vmm_mad' => $type, 
            'vnm_mad' => $vnm_mad
        );
        # to keep the record of our cloud infrastructure
        # we include the host in ONE db even if it fails
        my @hostinstances = $one->get_hosts(qr{^$host$});
        if (scalar(@hostinstances) > 1) {
            $self->error("Found more than one host $host. Only the first host will be modified.");
        }
        my $hostinstance = $hostinstances[0];
        if (exists($protected{$host})) {
            $self->info("This resource $type is protected and can not be created/updated: $host");
        } elsif ($self->can_connect_to_host($host)) {
            my $output = $self->enable_node($one, $type, $host, $resources);
            if ($output) {
                if ($hostinstance) {
                    # The host is already available and OK
                    $hostinstance->enable if !$hostinstance->is_enabled;
                    $self->info("Enabled existing host $host");
                } else {
                    # The host is not available yet from ONE framework
                    # and it is running correctly
                    $new = $one->create_host(%host_options);
                    $self->update_something($one, "host", $host, "QUATTOR = 1");
                    $self->info("Created new $type host $host.");
                }
            } else {
                $self->
                disable_host($one, $type, $host, $hostinstance, %host_options);
            }
        } else {
            push(@failedhost, $host);
            $self->
            disable_host($one, $type, $host, $hostinstance, %host_options);
        }
    }

    if (@failedhost) {
        $self->error("Detected some error/s including these $type nodes: ", join(', ', @failedhost));
    }

}

# Disables failing hyp
sub disable_host
{
    my ($self, $one, $type, $host, $hostinstance, %host_options) = @_;

    $self->warn("Could not connect to $type host: $host.");
    if ($hostinstance) {
        $hostinstance->disable;
        $self->info("Disabled existing host $host");
    } else {
        my $new = $one->create_host(%host_options);
        $new->disable;
        $self->info("Created and disabled new host $host");
    }
}

# Function to add/remove/update regular users
# only if the user has the Quattor flag set
sub manage_users
{
    my ($self, $one, $users, %protected) = @_;
    my ($new, $template, @rmusers, @userlist);

    foreach my $user (@$users) {
        if ($user->{user}) {
            if ($user->{user} eq "serveradmin" && exists $user->{password}) {
                $self->change_opennebula_passwd($user->{user}, $user->{password});
            }
            push(@userlist, $user->{user});
        }
    }

    my @exitsuser = $one->get_users();
    my %newusers = map { $_ => 1 } @userlist;

    foreach my $t (@exitsuser) {
        # Remove the user only if the QUATTOR flag is set
        my $quattor = $self->check_quattor_tag($t,1);
        if (exists($protected{$t->name})) {
            $self->info("This user is protected and can not be removed: ", $t->name);
        } elsif (exists($newusers{$t->name})) {
            $self->verbose("User required by Quattor. We can't remove it: ", $t->name);
        } elsif (!$quattor) {
            $self->warn("QUATTOR flag not found. We can't remove this user: ", $t->name);
        } else {
            push(@rmusers, $t->name);
            $t->delete();
        }
    }

    if (@rmusers) {
        $self->info("Removed users: ", join(',', @rmusers));
    }

    foreach my $user (@$users) {
        if (exists($protected{$user->{user}})) {
            $self->info("This user is protected and can not be created/updated: ", $user->{user});
        } elsif ($user->{user} && $user->{password}) {
            $template = $self->process_template($user, "user");
            my $used = $self->detect_used_resource($one, "user", $user->{user});
            if (!$used) {
                $self->info("Creating new user: ", $user->{user});
                $one->create_user($user->{user}, $user->{password}, "core");
                # Add Quattor flag
                $new = $self->update_something($one, "user", $user->{user}, $template);
            } elsif ($used == -1) {
                # User is already there and we can modify it
                $self->info("Updating user with a new template: ", $user->{user});
                $new = $self->update_something($one, "user", $user->{user}, $template);
            }
        } else {
            $self->error("No user name or password info available:", $user->{user});
        }
    }
}

# Set opennebula conf files
# used by OpenNebula daemons
# if conf file is changed 
# one service must be restarted afterwards
sub set_one_service_conf
{
    my ($self, $data, $service, $config_file) = @_;
    my %opts;
    my $oned_templ = $self->process_template($data, $service);
    %opts = $self->set_file_opts();
    return if ! %opts;
    my $fh = $oned_templ->filewriter($config_file, %opts);
    my $status = $self->is_conf_file_modified($fh, $config_file, $service, $oned_templ);

    return $status;
}

# Checks conf file status
sub is_conf_file_modified
{
    my ($self, $fh, $file, $service, $data) = @_;

    if (!defined($fh)) {
        if (defined($service) && defined($data)) {
            $self->error("Failed to render $service file: $file (".$data->{fail}."). Skipping");
        } else {
            $self->error("Problem rendering $file");
        }
        $fh->cancel();
        $fh->close();
        return;
    }
    if ($fh->close()) {
        $self->restart_opennebula_service($service) if (defined($service));
    }
    return 1;
}

# Set auth files
# used by oneadmin client tools
sub set_one_auth_file
{
    my ($self, $user, $data) = @_;
    my ($fh, $auth_file, %opts);

    my $passwd = {$user => $data};
    my $trd = $self->process_template($passwd, "one_auth", 1);
    %opts = $self->set_file_opts(1);
    return if ! %opts;

    if ($user eq "oneadmin") {
        $self->verbose("Writing $user auth file: $ONEADMIN_AUTH_FILE");
        $fh = $trd->filewriter($ONEADMIN_AUTH_FILE, %opts);
        $self->is_conf_file_modified($fh, $ONEADMIN_AUTH_FILE);
    } elsif ($user eq "serveradmin") {
        foreach my $service (@SERVERADMIN_AUTH_FILE) {
            $auth_file = $SERVERADMIN_AUTH_DIR . $service;
            $self->verbose("Writing $user auth file: $auth_file");
            $fh = $trd->filewriter($auth_file, %opts);
            $self->is_conf_file_modified($fh, $auth_file);
        }
    } else {
        $self->error("Unsupported user: $user");
    }
}

# Configure OpenNebula server
sub set_one_server
{
    my($self, $tree) = @_;
    # Set ssh multiplex options
    $self->set_ssh_command($tree->{ssh_multiplex});
    # Set tm_system_ds if available
    my $tm_system_ds = $tree->{tm_system_ds};
    # untouchables resources
    my $untouchables = $tree->{untouchables};
    # hypervisor type
    my $hypervisor = $tree->{host_hyp};

    # Change oneadmin pass
    if (exists $tree->{rpc}->{password}) {
        return 0 if !$self->change_opennebula_passwd("oneadmin", $tree->{rpc}->{password});
    }

    # Configure ONE RPC connector
    my $one = $self->make_one($tree->{rpc});
    if (! $one ) {
        $self->error("No ONE instance created.");
        return 0;
    };

    # Check ONE RPC endpoint and OpenNebula version
    return 0 if !$self->is_supported_one_version($one);

    $self->manage_something($one, "vnet", $tree->{vnets}, $untouchables->{vnets});

    # For the moment only Ceph and shared datastores are configured
    $self->manage_something($one, "datastore", $tree->{datastores}, $untouchables->{datastores});
    # Update system datastore TM_MAD
    if ($tm_system_ds) {
        $self->update_something($one, "datastore", "system", "TM_MAD = $tm_system_ds");
        $self->info("Updated system datastore TM_MAD = $tm_system_ds");
    }
    $self->manage_something($one, $hypervisor, $tree, $untouchables->{hosts});
    $self->manage_something($one, "user", $tree->{users}, $untouchables->{users});

    # Set kvmrc conf
    if (exists $tree->{kvmrc}) {
        $self->set_one_service_conf($tree->{kvmrc}, "kvmrc", $KVMRC_CONF_FILE);
    }

    return 1;
}

# Set filewriter options
# do not show logs if it contains passwds
sub set_file_opts
{
    my ($self, $secret) = @_;
    my %opts;
    if ($ONEADMINUSR and $ONEADMINGRP) {
        if (!$secret) {
            %opts = (log => $self);
        }
        %opts = (mode => 0600,
                 backup => ".quattor.backup",
                 owner => $ONEADMINUSR,
                 group => $ONEADMINGRP);
        $self->verbose("Found oneadmin user id ($ONEADMINUSR) and group id ($ONEADMINGRP).");
        return %opts;
    } else {
        $self->error("User or group oneadmin does not exist.");
        return;
    }
}

# Check ONE endpoint and detects ONE version
# returns false if ONE version is not supported by AII
sub is_supported_one_version
{
    my ($self, $one) = @_;

    my $oneversion = $one->version();

    if ($oneversion) {
        $self->info("Detected OpenNebula version: $oneversion");
    } else {
        $self->error("OpenNebula RPC endpoint is not reachable.");
        return;
    }

    my $res= $oneversion >= $MINIMAL_ONE_VERSION;
    if ($res) {
        $self->verbose("Version $oneversion is ok.");
    } else {
        $self->error("OpenNebula component requires ONE v$MINIMAL_ONE_VERSION or higher (found $oneversion).");
    }
    return $res;
}

# Configure basic ONE resources
sub Configure
{
    my ($self, $config) = @_;

    # Define paths for convenience.
    my $base = "/software/components/opennebula";
    my $tree = $config->getElement($base)->getTree();

    # Set oned.conf
    if (exists $tree->{oned}) {
        $self->set_one_service_conf($tree->{oned}, "oned", $ONED_CONF_FILE);
    }

    # Set Sunstone server
    if (exists $tree->{sunstone}) {
        $self->set_one_service_conf($tree->{sunstone}, "sunstone", $SUNSTONE_CONF_FILE);
        if (exists $tree->{users}) {
            my $users = $tree->{users};
            foreach my $user (@$users) {
                if ($user->{user} eq "serveradmin" && exists $user->{password}) {
                    $self->set_one_auth_file($user->{user}, $user->{password});
                }
            }
        }
    }

    # Set OpenNebula server
    if (exists $tree->{rpc}) {
        return $self->set_one_server($tree);
    }

    return 1;
}

1;

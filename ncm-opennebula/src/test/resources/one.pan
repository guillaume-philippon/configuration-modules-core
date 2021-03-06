template one;

prefix "/software/components/opennebula/rpc";
"user" = "oneadmin";
"password" = "verysecret";
"host" = "myhost.domain";
"port" = 1234;

prefix "/software/components/opennebula/untouchables";
"datastores" = list('system');

prefix "/software/components/opennebula/oned";
"db" = dict(
    "backend", "mysql",
    "server", "localhost",
    "port", 0,
    "user", "oneadmin",
    "passwd", "my-fancy-pass",
    "db_name", "opennebula",
);
"log" = dict(
    "system", "syslog",
    "debug_level", 3,
);
"default_device_prefix" = "vd";
"onegate_endpoint" = "http://hyp004.cubone.os:5030";

prefix "/software/components/opennebula/sunstone";
"host" = "0.0.0.0";
"tmpdir" = "/tmp";

prefix "/software/components/opennebula/kvmrc";
"qemu_protocol" = "qemu+tcp";
"force_destroy" = true;

prefix "/software/components/opennebula";

"vnets" = list(
    dict(
        "name", "altaria.os",
        "bridge", "br100",
        "gateway", "10.141.3.250",
        "dns", "10.141.3.250",
        "network_mask", "255.255.0.0"
    ),
    dict(
        "name", "altaria.vsc",
        "bridge", "br101",
        "gateway", "10.141.3.250",
        "dns", "10.141.3.250",
        "network_mask", "255.255.0.0"
    ),
    dict(
        "name", "pool.altaria.os",
        "bridge", "br100",
        "bridge_ovs", "ovsbr0",
        "gateway", "10.141.3.250",
        "dns", "10.141.3.250",
        "network_mask", "255.255.0.0",
        "vlan", true,
        "vlan_id", 0,
        "ar", dict(
                    "type", "IP4",
                    "ip", "10.141.14.100",
                    "size", 29
        ),
    ),
);

"datastores" = list(
    dict(
        "name", "ceph.altaria",
        "bridge_list", list("hyp004.cubone.os"),
        "ceph_host", list("ceph001.cubone.os","ceph002.cubone.os","ceph003.cubone.os"),
        "ceph_secret", "8371ae8a-386d-44d7-a228-c42de4259c6e",
        "ceph_user", "libvirt",
        "datastore_capacity_check", true,
        "ceph_user_key", "AQCGZr1TeFUBMRBBHExosSnNXvlhuKexxcczpw==",
        "pool_name", "one",
        "type", "IMAGE_DS"
    ),
    dict(
        "name", "nfs",
        "datastore_capacity_check", true,
        "ds_mad", "fs",
        "tm_mad", "shared",
        "type", "IMAGE_DS",
    ),
);

"users" = list(
    dict(
        "user", "lsimngar",
        "password", "my_fancy_pass",
        "ssh_public_key", "ssh-dss AAAAB3NzaC1kc3MAAACBAOTAivURhUrg2Zh3DqgVd2ofRYKmXKjWDM4LITQJ/Tr6RBWhufdxmJos/w0BG9jFbPWbUyPn1mbRFx9/2JJjaspJMACiNsQV5KD2a2H/yWVBxNkWVUwmq36JNh0Tvx+ts9Awus9MtJIxUeFdvT433DePqRXx9EtX9WCJ1vMyhwcFAAAAFQDcuA4clpwjiL9E/2CfmTKHPCAxIQAAAIEAnCQBn1/tCoEzI50oKFyF5Lvum/TPxh6BugbOKu18Okvwf6/zpsiUTWhpxaa40S4FLzHFopTklTHoG3JaYHuksdP4ZZl1mPPFhCTk0uFsqfEVlK9El9sQak9vXPIi7Tw/dyylmRSq+3p5cmurjXSI93bJIRv7X4pcZlIAvHWtNAYAAACBAOCkwou/wYp5polMTqkFLx7dnNHG4Je9UC8Oqxn2Gq3uu088AsXwaVD9t8tTzXP1FSUlG0zfDU3BX18Ds11p57GZtBSECAkqH1Q6vMUiWcoIwj4hq+xNq3PFLmCG/QP+5Od5JvpbBKqX9frc1UvOJJ3OKSjgWMx6FfHr8PxqqACw lsimngar@OptiPlex-790",
        "quattor", 1
    ),
    dict(
        "user", "stdweird",
        "password", "another_fancy_pass",
        "quattor", 1
    ),
    dict(
        "user", "serveradmin",
        "password", "yet_another_fancy_pass",
    ),
);

"hosts" = list(
    'hyp101', 'hyp102', 'hyp103', 'hyp104'
);

"ssh_multiplex" = true;
"host_hyp" = "kvm";
"host_ovs" = true;
"tm_system_ds" = "ssh";


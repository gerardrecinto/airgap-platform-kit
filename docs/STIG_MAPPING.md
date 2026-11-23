# STIG mapping

The `stig_baseline` Puppet module implements a small subset of settings that
align to the DISA STIG for Red Hat Enterprise Linux 9. It is "aligned to"
those controls only. It is not a compliance claim, not certified, and has not
been scanned with a SCAP tool on a real RHEL host. Unit tests check the
rendered configuration, and a Puppet `--noop` run was done on a Rocky Linux 9
container (see the README).

STIG IDs below were taken from a public STIG listing for RHEL 9. Rule numbers
change between benchmark releases, so check each ID against the release you
are assessed against before you rely on this table.

## Implemented controls

| Area | Setting | Default | STIG ID | Puppet parameter |
|------|---------|---------|---------|------------------|
| sshd | `PermitRootLogin no` | no | RHEL-09-255045 | `stig_baseline::ssh::permit_root_login` |
| sshd | `PermitEmptyPasswords no` | no | RHEL-09-255040 | `stig_baseline::ssh::permit_empty_passwords` |
| sshd | `Ciphers` limited to FIPS-approved list | 4 ciphers | RHEL-09-255065 | `stig_baseline::ssh::ciphers` |
| sshd | `MACs` limited to FIPS-approved list | 4 MACs | RHEL-09-255075 | `stig_baseline::ssh::macs` |
| sshd | `ClientAliveInterval 600`, `ClientAliveCountMax 1` | 600 / 1 | RHEL-09-255095, RHEL-09-255100 | `client_alive_interval`, `client_alive_count_max` |
| sshd | `X11Forwarding no` | no | RHEL-09-255155 | `stig_baseline::ssh::x11_forwarding` |
| sshd | `IgnoreRhosts yes` | yes | RHEL-09-255145 | `stig_baseline::ssh::ignore_rhosts` |
| sshd | `UsePAM yes` | yes | RHEL-09-255050 | `stig_baseline::ssh::use_pam` |
| sshd | `Banner /etc/issue` | /etc/issue | RHEL-09-255025 | `stig_baseline::ssh::banner_path` |
| banner | Text in `/etc/issue` and `/etc/issue.net` | generic notice | RHEL-09-211020 | `stig_baseline::banner::banner_text` |
| faillock | `deny = 3` | 3 | RHEL-09-411075 | `stig_baseline::auth::faillock_deny` |
| faillock | `fail_interval = 900` | 900 s | RHEL-09-411085 | `stig_baseline::auth::faillock_fail_interval` |
| faillock | `unlock_time = 0` (admin unlock) | 0 | RHEL-09-411090 | `stig_baseline::auth::faillock_unlock_time` |
| pwquality | `minlen = 15` | 15 | RHEL-09-611090 | `stig_baseline::auth::pwquality` |
| pwquality | `dcredit = -1` | -1 | RHEL-09-611070 | same map |
| pwquality | `ucredit = -1` | -1 | RHEL-09-611110 | same map |
| pwquality | `lcredit = -1` | -1 | RHEL-09-611065 | same map |
| pwquality | `ocredit = -1` | -1 | RHEL-09-611100 | same map |
| pwquality | `difok = 8` | 8 | RHEL-09-611115 | same map |
| auditd | Watch `/etc/passwd` | wa | RHEL-09-654240 | `stig_baseline::audit::watches` |
| auditd | Watch `/etc/shadow` | wa | RHEL-09-654245 | same map |
| auditd | Watch `/etc/group` | wa | RHEL-09-654225 | same map |
| auditd | Watch `/etc/sudoers` and `/etc/sudoers.d/` | wa | RHEL-09-654215 | same map |
| sysctl | `net.ipv4.ip_forward = 0` | 0 (1 for RKE2) | RHEL-09-253075 | `stig_baseline::sysctl::settings` |
| sysctl | `net.ipv4.conf.all.accept_source_route = 0` | 0 | RHEL-09-253020 | same map |
| sysctl | `net.ipv4.conf.default.accept_source_route = 0` | 0 | RHEL-09-253045 | same map |
| sysctl | `net.ipv4.conf.all.send_redirects = 0` | 0 | RHEL-09-253065 | same map |
| sysctl | `net.ipv4.tcp_syncookies = 1` | 1 | RHEL-09-253010 | same map |
| sysctl | `kernel.randomize_va_space = 2` | 2 | RHEL-09-213070 | same map |
| sysctl | `kernel.kptr_restrict = 1` | 1 | RHEL-09-213025 | same map |
| sysctl | `kernel.dmesg_restrict = 1` | 1 | RHEL-09-213010 | same map |
| sysctl | `kernel.yama.ptrace_scope = 1` | 1 | RHEL-09-213080 | same map |
| file perms | `/etc/passwd` 0644 root:root | 0644 | RHEL-09-232075, RHEL-09-232130, RHEL-09-232135 | `stig_baseline::permissions::file_modes` |
| file perms | `/etc/group` 0644 root:root | 0644 | RHEL-09-232055, RHEL-09-232090, RHEL-09-232095 | same map |
| file perms | `/etc/shadow` 0000 root:root | 0000 | RHEL-09-232270, RHEL-09-232150, RHEL-09-232155 | same map |
| file perms | `/etc/gshadow` 0000 root:root | 0000 | RHEL-09-232065, RHEL-09-232110, RHEL-09-232115 | same map |

## Documented exception

RKE2 nodes forward pod traffic, so `net.ipv4.ip_forward` must be 1. The role
data in `puppet/hiera/role/rke2_node.yaml` sets it, and the Ansible role
applies that role by default (`airgap_puppet_role: rke2_node`). That is a
deliberate deviation from RHEL-09-253075 and needs an entry in your own
exception register.

## Not covered

Plenty of the STIG is out of scope here, including FIPS mode, partitioning and
mount options, SELinux state, `pam_faillock` wiring in the PAM stack through
`authselect` (RHEL-09-611030, RHEL-09-611035), password aging, AIDE, USBGuard,
the full set of audit rules for syscalls, and `HostbasedAuthentication`. Do
not read this module as a full STIG implementation.

## Site overrides

The banner text in `data/common.yaml` is a generic placeholder. Sites that
must show a specific notice override `stig_baseline::banner::banner_text`
in their own Hiera data.

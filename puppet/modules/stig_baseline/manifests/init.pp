# @summary Applies the STIG-aligned baseline subset for RHEL 9.
#
# Each area can be switched off. Per-area settings live in the subclasses
# and are bound from module Hiera data.
#
# @param manage_ssh Manage sshd hardening drop-in.
# @param manage_audit Manage auditd rules.
# @param manage_auth Manage faillock and pwquality settings.
# @param manage_sysctl Manage kernel sysctl settings.
# @param manage_permissions Manage permissions on account files.
# @param manage_banner Manage the login banner files.
class stig_baseline (
  Boolean $manage_ssh         = true,
  Boolean $manage_audit       = true,
  Boolean $manage_auth        = true,
  Boolean $manage_sysctl      = true,
  Boolean $manage_permissions = true,
  Boolean $manage_banner      = true,
) {
  if $facts['os']['family'] != 'RedHat' {
    fail("stig_baseline supports the RedHat family only, got ${facts['os']['family']}")
  }

  if $manage_banner {
    include stig_baseline::banner
  }
  if $manage_ssh {
    include stig_baseline::ssh
  }
  if $manage_audit {
    include stig_baseline::audit
  }
  if $manage_auth {
    include stig_baseline::auth
  }
  if $manage_sysctl {
    include stig_baseline::sysctl
  }
  if $manage_permissions {
    include stig_baseline::permissions
  }
}

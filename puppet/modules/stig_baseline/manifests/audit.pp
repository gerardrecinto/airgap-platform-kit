# @summary auditd watch rules for account and sudo files.
#
# @param watches Map of path to audit key.
# @param rules_file Rules drop-in path.
# @param service_name auditd service name.
class stig_baseline::audit (
  Hash[String, String] $watches,
  String               $rules_file,
  String               $service_name,
) {
  file { $rules_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0640',
    content => epp('stig_baseline/audit.rules.epp', { 'watches' => $watches }),
    notify  => Exec['stig_baseline_augenrules'],
  }

  exec { 'stig_baseline_augenrules':
    command     => '/usr/sbin/augenrules --load',
    refreshonly => true,
  }

  # auditd refuses a manual restart through systemctl on RHEL, so only enable.
  service { $service_name:
    enable => true,
  }
}

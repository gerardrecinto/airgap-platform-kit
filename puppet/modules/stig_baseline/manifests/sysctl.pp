# @summary Kernel sysctl settings in a drop-in file.
#
# Kubernetes nodes need net.ipv4.ip_forward = 1. Override it in Hiera for
# those roles and record the exception.
#
# @param settings Map of sysctl key to value.
# @param conf_file Drop-in path.
class stig_baseline::sysctl (
  Hash[String, Variant[Integer, String]] $settings,
  String                                 $conf_file,
) {
  file { $conf_file:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('stig_baseline/sysctl.conf.epp', { 'settings' => $settings }),
    notify  => Exec['stig_baseline_sysctl_reload'],
  }

  exec { 'stig_baseline_sysctl_reload':
    command     => '/usr/sbin/sysctl --system',
    refreshonly => true,
  }
}

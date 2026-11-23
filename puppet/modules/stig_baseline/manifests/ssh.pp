# @summary sshd hardening through a drop-in file.
#
# The drop-in sorts before most local files, and sshd uses the first value it
# sees, so these settings win over later config.
#
# @param ciphers Allowed ciphers.
# @param macs Allowed MACs.
# @param permit_root_login Value for PermitRootLogin.
# @param permit_empty_passwords Value for PermitEmptyPasswords.
# @param client_alive_interval Seconds between keepalive probes.
# @param client_alive_count_max Missed probes before disconnect.
# @param x11_forwarding Value for X11Forwarding.
# @param ignore_rhosts Value for IgnoreRhosts.
# @param use_pam Value for UsePAM.
# @param banner_path File shown before login.
# @param config_dir sshd drop-in directory.
# @param service_name sshd service name.
class stig_baseline::ssh (
  Array[String]  $ciphers,
  Array[String]  $macs,
  String         $permit_root_login,
  Boolean        $permit_empty_passwords,
  Integer        $client_alive_interval,
  Integer        $client_alive_count_max,
  Boolean        $x11_forwarding,
  Boolean        $ignore_rhosts,
  Boolean        $use_pam,
  String         $banner_path,
  String         $config_dir,
  String         $service_name,
) {
  file { "${config_dir}/50-stig-baseline.conf":
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0600',
    content => epp('stig_baseline/sshd_stig.conf.epp', {
      'ciphers'                => $ciphers,
      'macs'                   => $macs,
      'permit_root_login'      => $permit_root_login,
      'permit_empty_passwords' => $permit_empty_passwords,
      'client_alive_interval'  => $client_alive_interval,
      'client_alive_count_max' => $client_alive_count_max,
      'x11_forwarding'         => $x11_forwarding,
      'ignore_rhosts'          => $ignore_rhosts,
      'use_pam'                => $use_pam,
      'banner_path'            => $banner_path,
    }),
    notify  => Service[$service_name],
  }

  service { $service_name:
    ensure => running,
    enable => true,
  }
}

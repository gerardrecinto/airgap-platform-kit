# @summary faillock and password quality settings.
#
# This class writes the config files only. Enabling the pam_faillock
# feature in the PAM stack (authselect) is not covered.
#
# @param faillock_deny Failed attempts before lock.
# @param faillock_fail_interval Window in seconds for counting failures.
# @param faillock_unlock_time Seconds locked, 0 means until an admin unlocks.
# @param faillock_conf faillock.conf path.
# @param pwquality_conf pwquality drop-in path.
# @param pwquality Map of pwquality option to value.
class stig_baseline::auth (
  Integer              $faillock_deny,
  Integer              $faillock_fail_interval,
  Integer              $faillock_unlock_time,
  String               $faillock_conf,
  String               $pwquality_conf,
  Hash[String,Integer] $pwquality,
) {
  file { $faillock_conf:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('stig_baseline/faillock.conf.epp', {
      'deny'          => $faillock_deny,
      'fail_interval' => $faillock_fail_interval,
      'unlock_time'   => $faillock_unlock_time,
    }),
  }

  file { $pwquality_conf:
    ensure  => file,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => epp('stig_baseline/pwquality.conf.epp', { 'options' => $pwquality }),
  }
}

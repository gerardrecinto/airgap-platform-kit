# @summary Writes the pre-login banner (RHEL-09-211020, RHEL-09-255025).
#
# @param banner_text Banner body. Sites must override with their required text.
# @param issue_files Files that receive the banner.
class stig_baseline::banner (
  String        $banner_text,
  Array[String] $issue_files,
) {
  $issue_files.each |String $path| {
    file { $path:
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => "${banner_text}\n",
    }
  }
}

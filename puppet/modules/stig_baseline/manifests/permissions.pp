# @summary Owner and mode on account database files.
#
# @param file_modes Map of path to file attributes.
class stig_baseline::permissions (
  Hash[String, Hash] $file_modes,
) {
  $file_modes.each |String $path, Hash $attrs| {
    file { $path:
      * => $attrs,
    }
  }
}

# == Class: consul_alerts
#
# The consul_alerts class currently contains installation and configuration for the consul_alerts
# puppet module. This will install a binary release of the consul-alerts service and
# launch it with upstart init system.
#
# === Parameters
#
# [*enabled*]
#   Enable the class as installed or not
#   Can be true or false (bool)
# [*binary_path*]
#   The system path in which to install the consul-alerts binary download
# [*version*]
#   A string containing the release version to install
# [*repo_url*]
#   Default repository URL from which to download the binary release
# [*arch*]
#   Server architecture version amd64/i386
# [*default_url*]
#   Use the default repository and download url either true or false (bool)
# [*custom_url*]
#   If you want to specify a custom download filename/location, specify it here
# [*alert_addr*]
#   Location to run the consul-alert service API on. Defaults to 127.0.0.1:9000
# [*consul_url*]
#   URL for the consul instance you want to use with alerts service
# [*data_center*]
#   Specify the data-center name in which to run the consul-alerts checks and k/v lookups
# [*watch_events*]
#   Boolean value for if event notifications from consul should be watched
# [*watch_checks*]
#   Boolean value for check update notifications from consul
#
# === Examples
#
#  class { 'consul_alerts':
#    consul_url  => '127.0.0.1:8500',
#    data_center => 'dc1',
#  }
#
# === Authors
#
# Justice London <jlondon@syrussystems.com>
#
# === Copyright
#
# Copyright 2015 Justice London
#
class consul_alerts (
  $enabled      = true,
  $binary_path  = '/usr/local/bin',
  $version      = '0.3.1',
  $repo_url     = 'https://github.com/Interencheres/consul-alerts/releases/download',
  $arch         = $::architecture,
  $default_url  = true,
  $custom_url   = undef,
  $alert_addr   = '127.0.0.1:9000',
  $consul_url   = '127.0.0.1:8500',
  $data_center  = 'dc1',
  $watch_events = true,
  $watch_checks = true,
) {
  #Variable validations
  validate_bool($enabled)
  validate_bool($default_url)
  validate_bool($watch_events)
  validate_bool($watch_checks)
  validate_absolute_path($binary_path)
  validate_string($version)
  validate_string($repo_url)
  validate_string($arch)
  validate_string($alert_addr)
  validate_string($consul_url)
  validate_string($data_center)

  #Build the full download URL
  $filename     = "consul-alerts-${version}-linux-${arch}.tar"
  $download_url = $default_url ? {
    false   => $custom_url,
    default => "${repo_url}/v${version}/${filename}",
  }

  #Download consul-alerts binary
  include ::wget

  exec { 'download_consul_alerts':
    command => "wget -q --no-check-certificate ${download_url} -O /var/tmp/${filename}",
    path    => '/usr/bin:/usr/local/bin:/bin',
    unless  => "test -s /var/tmp/${filename}",
    notify  => Exec['extract_consul_alerts'],
  }

  #Install binary
  exec { 'extract_consul_alerts':
    command     => "tar -xf /var/tmp/${filename}",
    cwd         => $binary_path,
    refreshonly => true,
    path        => ['/bin', '/sbin', '/usr/bin', '/usr/sbin'],
    notify      => Service['consul-alerts'],
  }

  #Define present/absent as true/false. Still don't understand why this isn't a builtin.
  $file_ensure = $enabled ? {
    false   => absent,
    default => present,
  }

  if $::operatingsystem == 'Debian' {
    if versioncmp($::operatingsystemrelease, '8.0') < 0 {
      $init_style = 'debian'
    } else {
      $init_style = 'systemd'
    }
  }

  if $init_style == 'systemd' {

    file { '/lib/systemd/system/consul-alerts.service':
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      ensure  => $file_ensure,
      content => template('consul_alerts/consul_alerts.systemd.erb'),
      notify  => Exec['systemd_reload_consul_alerts'],
    }

    exec { "systemd_reload_consul_alerts":
      command     => '/bin/systemctl daemon-reload',
      refreshonly => true,
    }

    service { 'consul-alerts':
      ensure  => $enabled,
      enable  => $enabled,
      provider => $init_style,
      require => [
        Exec['extract_consul_alerts'],
        File['/lib/systemd/system/consul-alerts.service'],
      ],
    }

  } else {
    #Build init file
    file { '/etc/init/consul-alerts.conf':
      ensure  => $file_ensure,
      content => template('consul_alerts/initfile.erb'),
      notify  => Service['consul-alerts'],
    }

    service { 'consul-alerts':
      ensure  => $enabled,
      enable  => $enabled,
      require => [
        Exec['extract_consul_alerts'],
        File['/etc/init/consul-alerts.conf'],
      ],
    }
  }

}

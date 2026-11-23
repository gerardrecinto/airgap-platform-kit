require 'spec_helper'

describe 'stig_baseline::sysctl' do
  let(:conf) { '/etc/sysctl.d/99-stig-baseline.conf' }

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_file(conf).that_notifies('Exec[stig_baseline_sysctl_reload]') }
  it { is_expected.to contain_file(conf).with_content(%r{^kernel.randomize_va_space = 2$}) }
  it { is_expected.to contain_file(conf).with_content(%r{^net.ipv4.tcp_syncookies = 1$}) }
  it { is_expected.to contain_file(conf).with_content(%r{^net.ipv4.ip_forward = 0$}) }

  context 'with the Kubernetes node override' do
    let(:params) { { settings: { 'net.ipv4.ip_forward' => 1 } } }

    it { is_expected.to contain_file(conf).with_content(%r{^net.ipv4.ip_forward = 1$}) }
  end
end

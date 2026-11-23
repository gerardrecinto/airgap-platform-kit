require 'spec_helper'

describe 'stig_baseline::ssh' do
  let(:path) { '/etc/ssh/sshd_config.d/50-stig-baseline.conf' }

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_file(path).with_mode('0600').with_owner('root').that_notifies('Service[sshd]') }
  it { is_expected.to contain_file(path).with_content(%r{^PermitRootLogin no$}) }
  it { is_expected.to contain_file(path).with_content(%r{^PermitEmptyPasswords no$}) }
  it { is_expected.to contain_file(path).with_content(%r{^Ciphers aes256-gcm@openssh.com,aes256-ctr,aes128-gcm@openssh.com,aes128-ctr$}) }
  it { is_expected.to contain_file(path).with_content(%r{^MACs hmac-sha2-512-etm@openssh.com}) }
  it { is_expected.to contain_file(path).with_content(%r{^ClientAliveInterval 600$}) }
  it { is_expected.to contain_file(path).with_content(%r{^X11Forwarding no$}) }
  it { is_expected.to contain_file(path).with_content(%r{^Banner /etc/issue$}) }
  it { is_expected.to contain_service('sshd').with_ensure('running').with_enable(true) }

  context 'with overridden parameters' do
    let(:params) { { client_alive_interval: 300, permit_root_login: 'prohibit-password' } }

    it { is_expected.to contain_file(path).with_content(%r{^ClientAliveInterval 300$}) }
    it { is_expected.to contain_file(path).with_content(%r{^PermitRootLogin prohibit-password$}) }
  end

  context 'with a wrong parameter type' do
    let(:params) { { client_alive_interval: 'ten' } }

    it { is_expected.to compile.and_raise_error(%r{client_alive_interval}) }
  end
end

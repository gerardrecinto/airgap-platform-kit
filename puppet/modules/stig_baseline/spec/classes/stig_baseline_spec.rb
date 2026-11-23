require 'spec_helper'

describe 'stig_baseline' do
  context 'with defaults on RHEL 9' do
    it { is_expected.to compile.with_all_deps }
    it { is_expected.to contain_class('stig_baseline::ssh') }
    it { is_expected.to contain_class('stig_baseline::audit') }
    it { is_expected.to contain_class('stig_baseline::auth') }
    it { is_expected.to contain_class('stig_baseline::sysctl') }
    it { is_expected.to contain_class('stig_baseline::permissions') }
    it { is_expected.to contain_class('stig_baseline::banner') }
  end

  context 'with areas switched off' do
    let(:params) { { manage_ssh: false, manage_audit: false } }

    it { is_expected.to compile.with_all_deps }
    it { is_expected.not_to contain_class('stig_baseline::ssh') }
    it { is_expected.not_to contain_class('stig_baseline::audit') }
    it { is_expected.to contain_class('stig_baseline::sysctl') }
  end

  context 'on a non RedHat family' do
    let(:facts) { { 'os' => { 'family' => 'Debian', 'name' => 'Debian', 'release' => { 'major' => '12' } } } }

    it { is_expected.to compile.and_raise_error(%r{RedHat family only}) }
  end
end

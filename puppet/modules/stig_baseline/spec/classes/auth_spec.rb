require 'spec_helper'

describe 'stig_baseline::auth' do
  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_file('/etc/security/faillock.conf').with_content(%r{^deny = 3$}) }
  it { is_expected.to contain_file('/etc/security/faillock.conf').with_content(%r{^fail_interval = 900$}) }
  it { is_expected.to contain_file('/etc/security/faillock.conf').with_content(%r{^unlock_time = 0$}) }
  it { is_expected.to contain_file('/etc/security/pwquality.conf.d/50-stig-baseline.conf').with_content(%r{^minlen = 15$}) }
  it { is_expected.to contain_file('/etc/security/pwquality.conf.d/50-stig-baseline.conf').with_content(%r{^dcredit = -1$}) }
  it { is_expected.to contain_file('/etc/security/pwquality.conf.d/50-stig-baseline.conf').with_content(%r{^difok = 8$}) }
end

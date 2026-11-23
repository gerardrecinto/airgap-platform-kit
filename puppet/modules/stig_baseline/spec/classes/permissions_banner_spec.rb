require 'spec_helper'

describe 'stig_baseline::permissions' do
  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_file('/etc/passwd').with_mode('0644').with_owner('root') }
  it { is_expected.to contain_file('/etc/group').with_mode('0644') }
  it { is_expected.to contain_file('/etc/shadow').with_mode('0000').with_group('root') }
  it { is_expected.to contain_file('/etc/gshadow').with_mode('0000') }
end

describe 'stig_baseline::banner' do
  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_file('/etc/issue').with_content(%r{Authorized use only}) }
  it { is_expected.to contain_file('/etc/issue.net').with_mode('0644') }
end

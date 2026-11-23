require 'spec_helper'

describe 'stig_baseline::audit' do
  let(:rules) { '/etc/audit/rules.d/50-stig-baseline.rules' }

  it { is_expected.to compile.with_all_deps }
  it { is_expected.to contain_file(rules).that_notifies('Exec[stig_baseline_augenrules]') }
  it { is_expected.to contain_file(rules).with_content(%r{^-w /etc/passwd -p wa -k identity$}) }
  it { is_expected.to contain_file(rules).with_content(%r{^-w /etc/shadow -p wa -k identity$}) }
  it { is_expected.to contain_file(rules).with_content(%r{^-w /etc/group -p wa -k identity$}) }
  it { is_expected.to contain_file(rules).with_content(%r{^-w /etc/sudoers -p wa -k actions$}) }
  it { is_expected.to contain_exec('stig_baseline_augenrules').with_refreshonly(true) }
end

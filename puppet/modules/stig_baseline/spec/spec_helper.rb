require 'puppetlabs_spec_helper/module_spec_helper'

RSpec.configure do |c|
  c.default_facts = {
    'networking' => { 'ip' => '10.0.0.1' },
    'os' => {
      'family' => 'RedHat',
      'name' => 'RedHat',
      'release' => { 'major' => '9', 'full' => '9.4' },
    },
  }
end

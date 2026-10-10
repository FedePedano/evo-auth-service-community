# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserTenants do
  let(:email) { 'owner@example.com' }

  def stub_rows(rows)
    result = double('ActiveRecord::Result', to_a: rows)
    connection = double('ActiveRecord::Connection')
    allow(connection).to receive(:exec_query).and_return(result)
    allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
    connection
  end

  describe '.active_slugs_for' do
    it 'returns the slugs of every active tenant the user belongs to' do
      stub_rows([{ 'slug' => 'acme' }, { 'slug' => 'globex' }])

      expect(described_class.active_slugs_for(email)).to eq(%w[acme globex])
    end

    it 'returns an empty array when the user has no active tenants' do
      stub_rows([])

      expect(described_class.active_slugs_for(email)).to eq([])
    end

    it 'accepts a user object and uses its email' do
      stub_rows([{ 'slug' => 'acme' }])
      user = double('User', email: 'Owner@Example.com')

      expect(described_class.active_slugs_for(user)).to eq(%w[acme])
    end

    it 'returns an empty array for a blank email without querying' do
      expect(ActiveRecord::Base).not_to receive(:connection)

      expect(described_class.active_slugs_for(nil)).to eq([])
      expect(described_class.active_slugs_for('   ')).to eq([])
    end

    it 'queries only active tenants with a matching membership' do
      connection = stub_rows([])

      expect(connection).to receive(:exec_query) do |sql, _name, binds|
        expect(sql).to include('public.tenants')
        expect(sql).to include('public.tenant_memberships')
        expect(sql).to include("t.status = 'active'")
        expect(sql).to match(/lower\(m\.email\)\s*=\s*\$1/)
        expect(binds.map(&:value)).to eq(['owner@example.com'])
        double('ActiveRecord::Result', to_a: [])
      end

      described_class.active_slugs_for(email)
    end

    it 'degrades to an empty array when the lookup raises (legacy install)' do
      allow(ActiveRecord::Base).to receive(:connection).and_raise(StandardError, 'no tenants table')

      expect(described_class.active_slugs_for(email)).to eq([])
    end
  end
end

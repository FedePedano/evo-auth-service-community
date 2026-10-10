# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JwtClaimsBuilder do
  let(:user) do
    double(
      'User',
      id: 42,
      email: 'owner@example.com',
      name: 'Owner',
      type: 'User',
      role_data: { 'name' => 'admin' }
    )
  end

  before do
    allow(UserTenants).to receive(:active_slugs_for).and_return(%w[acme globex])
  end

  describe '.build' do
    subject(:claims) { described_class.build(user: user, expires_in: 3600, setup_active: true) }

    it 'adds tenants as an array of active slugs' do
      expect(claims[:tenants]).to eq(%w[acme globex])
    end

    it 'preserves every existing claim' do
      expect(claims).to include(
        iss: 'evo-auth-service',
        aud: '[]',
        sub: '42',
        email: 'owner@example.com',
        name: 'Owner',
        type: 'User',
        role: { 'name' => 'admin' },
        setup_active: true
      )
      expect(claims[:jti]).to be_a(String).and be_present
      expect(claims[:iat]).to be_a(Integer)
      expect(claims[:exp]).to be > claims[:iat]
    end

    it 'contains exactly the previous claims plus tenants' do
      expected_keys = %i[iss aud jti iat exp sub email name type role setup_active tenants]

      expect(claims.keys).to match_array(expected_keys)
    end

    it 'reads iss/aud from the environment like the previous implementation' do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with('DOORKEEPER_JWT_ISS', 'evo-auth-service').and_return('custom-iss')
      allow(ENV).to receive(:fetch).with('DOORKEEPER_JWT_AUD', '[]').and_return('["aud1"]')

      expect(claims[:iss]).to eq('custom-iss')
      expect(claims[:aud]).to eq('["aud1"]')
    end

    it 'omits tenants for anonymous tokens (no resource owner)' do
      anonymous = described_class.build(user: nil, expires_in: 3600, setup_active: false)

      expect(anonymous).not_to have_key(:tenants)
      expect(anonymous).not_to have_key(:sub)
      expect(anonymous).to include(iss: 'evo-auth-service', aud: '[]', setup_active: false)
      expect(anonymous[:jti]).to be_present
    end
  end
end

# frozen_string_literal: true

require 'rails_helper'
require 'doorkeeper/jwt'

# Fase 0.3: verifies that the claims produced by JwtClaimsBuilder flow through
# the current Doorkeeper::JWT signing mechanism (HS256 + secret) and are
# recoverable by JWT.decode.
RSpec.describe 'JWT claim signing/verification', type: :model do
  let(:secret) { 'unit-test-secret-key' }
  let(:signing_method) { :hs256 }
  let(:user) do
    double(
      'User', id: 7, email: 'owner@example.com', name: 'Owner',
      type: 'User', role_data: 'admin'
    )
  end

  before do
    allow(UserTenants).to receive(:active_slugs_for).and_return(%w[acme globex])

    signing_secret = secret
    Doorkeeper::JWT.configure do
      secret_key signing_secret
      signing_method :hs256
      token_payload do |opts|
        JwtClaimsBuilder.build(
          user: opts[:user],
          expires_in: opts[:expires_in],
          setup_active: false
        )
      end
    end
  end

  def decode(token)
    JWT.decode(token, secret, true, algorithm: signing_method.to_s.upcase).first
  end

  it 'signs the tenants claim and every existing claim into a verifiable token' do
    token = Doorkeeper::JWT.generate(user: user, expires_in: 3600)
    decoded = decode(token)

    expect(decoded['tenants']).to eq(%w[acme globex])
    expect(decoded['sub']).to eq('7')
    expect(decoded['email']).to eq('owner@example.com')
    expect(decoded['role']).to eq('admin')
  end

  it 'rejects a token signed with a different secret' do
    token = Doorkeeper::JWT.generate(user: user, expires_in: 3600)

    expect { JWT.decode(token, 'wrong-secret', true, algorithm: signing_method.to_s.upcase) }
      .to raise_error(JWT::VerificationError)
  end

  it 'issues legacy-shaped tokens (no tenants) for anonymous owners' do
    token = Doorkeeper::JWT.generate(user: nil, expires_in: 3600)
    decoded = decode(token)

    expect(decoded).not_to have_key('tenants')
    expect(decoded).not_to have_key('sub')
  end
end

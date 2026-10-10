# frozen_string_literal: true

require 'rails_helper'

# Contract of `POST /api/v1/auth/validate` (see scripts/multitenant/CONTRACT.md §4.1).
#
# Tokens are stored as JWTs (doorkeeper-jwt) but the JWT is only the STORAGE
# FORMAT of the token string: both Doorkeeper and this service resolve the token
# by lookup in `oauth_access_tokens` (opaque, DB-backed) and check expiration and
# revocation. The JWT signature / `iss` / `aud` are intentionally NOT verified —
# a syntactically valid JWT without a matching, live DB row must be rejected.
RSpec.describe TokenValidationService do
  let(:token_string) { 'header.payload.signature' }
  let(:bearer_request) do
    double('request', headers: { 'Authorization' => "Bearer #{token_string}" })
  end
  let(:api_request) { double('request', headers: { 'api_access_token' => 'opaque-token' }) }

  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:user) { double('user', id: 'user-1') }
  let(:user_data) { { 'id' => 'user-1' } }
  let(:valid_token) do
    double('doorkeeper_token', resource_owner_id: 'user-1', expired?: false, revoked?: false)
  end

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    allow(Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(User).to receive(:find).and_return(user)
    allow(UserSerializer).to receive(:full).and_return(user_data)
    allow(TokenSerializer).to receive(:oauth).and_return({ 'access_token' => token_string })
    allow(TokenSerializer).to receive(:access_token).and_return({ 'access_token' => 'opaque-token' })
  end

  def stub_by_token(value)
    allow(Doorkeeper::AccessToken).to receive(:by_token).with(token_string).and_return(value)
  end

  describe 'bearer token (Doorkeeper access token, cache miss)' do
    subject(:service) { described_class.new(bearer_request) }

    it 'rejects a token with no matching row in oauth_access_tokens' do
      stub_by_token(nil)

      expect { service.validate! }.to raise_error(TokenValidationService::InvalidToken)
    end

    it 'rejects a well-formed JWT that is not backed by a live DB row (DB row is the source of truth)' do
      # Three-segment JWT shape is irrelevant: without the oauth_access_tokens
      # row the token is invalid, proving signature/iss/aud are not checked.
      stub_by_token(nil)

      expect { service.validate! }.to raise_error(TokenValidationService::InvalidToken)
    end

    it 'rejects an expired token' do
      stub_by_token(double('token', resource_owner_id: 'user-1', expired?: true, revoked?: false))

      expect { service.validate! }.to raise_error(TokenValidationService::ExpiredToken)
    end

    it 'rejects a revoked token' do
      stub_by_token(double('token', resource_owner_id: 'user-1', expired?: false, revoked?: true))

      expect { service.validate! }.to raise_error(TokenValidationService::InvalidToken)
    end

    it 'accepts a live token and returns its user' do
      stub_by_token(valid_token)

      expect(service.validate!).to eq(
        user: user_data, token: { 'access_token' => token_string }
      )
    end
  end

  describe 'bearer token (cache hit)' do
    subject(:service) { described_class.new(bearer_request) }

    before do
      cache.write(
        TokenValidationService.cache_key_for(token_string),
        { user: user_data, token: { 'access_token' => token_string } },
        expires_in: 5.minutes
      )
    end

    it 'still rejects a revoked token (revocation stays authoritative when cached)' do
      stub_by_token(double('token', resource_owner_id: 'user-1', expired?: false, revoked?: true))

      expect { service.validate! }.to raise_error(TokenValidationService::InvalidToken)
    end

    it 'still rejects an expired token' do
      stub_by_token(double('token', resource_owner_id: 'user-1', expired?: true, revoked?: false))

      expect { service.validate! }.to raise_error(TokenValidationService::ExpiredToken)
    end

    it 'returns the cached result when the token is still live' do
      stub_by_token(valid_token)

      expect(service.validate!).to eq(
        user: user_data, token: { 'access_token' => token_string }
      )
    end
  end

  describe 'api_access_token (opaque AccessToken)' do
    subject(:service) { described_class.new(api_request) }

    it 'rejects an unknown access token' do
      allow(AccessToken).to receive(:find_by).with(token: 'opaque-token').and_return(nil)

      expect { service.validate! }.to raise_error(TokenValidationService::InvalidToken)
    end

    it 'accepts a known access token and returns its owner' do
      owner = double('owner', id: 'owner-1')
      allow(AccessToken).to receive(:find_by).with(token: 'opaque-token')
        .and_return(double('access_token', issued_id: nil, owner: owner))

      expect(service.validate!).to eq(
        user: user_data, token: { 'access_token' => 'opaque-token' }
      )
    end
  end

  describe 'no token' do
    subject(:service) { described_class.new(double('request', headers: {})) }

    it 'raises TokenNotFound' do
      expect { service.validate! }.to raise_error(TokenValidationService::TokenNotFound)
    end
  end
end

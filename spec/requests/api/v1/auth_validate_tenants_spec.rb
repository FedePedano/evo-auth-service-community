# frozen_string_literal: true

require 'rails_helper'

# Contract: `data.tenants` in POST /api/v1/auth/validate is exactly a flat
# `string[]` of the caller's ACTIVE tenant slugs. It must never expose
# schema_name/plan/role, must exclude inactive tenants, and must only include
# tenants where the user's email holds a membership.
RSpec.describe 'POST /api/v1/auth/validate — tenants contract', type: :request do
  let(:password) { 'Valid1!Pass' }

  let(:user) do
    User.create!(
      name: 'Tenants User',
      email: "tenants-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  let(:token) { AccessToken.create!(owner: user, name: 'tenants-token', scopes: 'default') }
  let(:headers) { { 'api_access_token' => token.token, 'Host' => 'localhost' } }

  def validate!
    post '/api/v1/auth/validate', headers: headers
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['data']
  end

  # Inserts one registry row for `slug` plus the membership for `email`.
  # Mirrors evo-ai-crm-community/db/migrate/20261001000001_create_tenants_registry.rb.
  def add_tenant(slug:, status: 'active', email: user.email)
    connection = ActiveRecord::Base.connection
    tenant_id = SecureRandom.uuid
    connection.execute(<<~SQL)
      INSERT INTO public.tenants (id, slug, schema_name, status, plan)
      VALUES (#{connection.quote(tenant_id)}, #{connection.quote(slug)},
              #{connection.quote("cliente_#{slug}")}, #{connection.quote(status)}, 'free');
      INSERT INTO public.tenant_memberships (id, tenant_id, user_id, role, email)
      VALUES (#{connection.quote(SecureRandom.uuid)}, #{connection.quote(tenant_id)},
              #{connection.quote(SecureRandom.uuid)}, 'owner', #{connection.quote(email.to_s.downcase)});
    SQL
    tenant_id
  end

  it 'returns exactly the slugs as a flat string array for multiple tenants' do
    user
    add_tenant(slug: 'acme')
    add_tenant(slug: 'globex')

    expect(validate!['tenants']).to eq(%w[acme globex])
  end

  it 'excludes inactive tenants and never leaks schema_name/plan/role' do
    user
    add_tenant(slug: 'acme')
    add_tenant(slug: 'globex', status: 'suspended')

    tenants = validate!['tenants']

    expect(tenants).to eq(%w[acme])
    expect(tenants).to all(be_a(String))
  end

  it 'returns an empty array when the user has no tenants' do
    user

    expect(validate!['tenants']).to eq([])
  end

  it 'only includes tenants where the email holds a membership' do
    user
    add_tenant(slug: 'acme')
    add_tenant(slug: 'globex', email: 'someone-else@example.com')

    expect(validate!['tenants']).to eq(%w[acme])
  end

  it 'keeps the rest of the response payload untouched' do
    allow(RuntimeConfig).to receive(:account).and_return({ 'id' => 1, 'name' => 'Acme' })
    user
    add_tenant(slug: 'acme')

    data = validate!

    expect(data['tenants']).to eq(%w[acme])
    expect(data['user']).to include('email' => user.email)
    expect(data['token']).to be_a(Hash)
    expect(data['accounts']).to be_an(Array)
  end
end

# frozen_string_literal: true

require 'rails_helper'

# Leak-harness multitenant A2 (Fase 0.6) — Auth boundary.
#
# POST /api/v1/auth/validate is the single source of truth for the
# `tenants: string[]` a token is scoped to. This spec pins the fail-closed
# contract that every downstream service (Flow BearerAuthGuard, CRM
# TenantSwitcher) relies on:
#   - a caller only ever receives its OWN active tenant slugs (A never sees B);
#   - inactive tenants are excluded (fail closed);
#   - a user without memberships receives [] — never a `default` tenant;
#   - an invalid token returns 401 and emits no tenant list at all;
#   - `tenants` stays a flat `string[]` (no schema_name/plan/role leakage).
#
# Registry tables (`public.tenants` / `public.tenant_memberships`) are created
# by spec/support/tenants_registry_tables.rb (mirrors the CRM migration
# 20261001000001_create_tenants_registry.rb).
RSpec.describe 'POST /api/v1/auth/validate — tenant leak boundary', type: :request do
  let(:password) { 'Valid1!Pass' }

  def create_user(label)
    User.create!(
      name: label,
      email: "#{label}-#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      confirmed_at: Time.current
    )
  end

  def token_for(user)
    AccessToken.create!(
      owner: user,
      name: "leak-#{SecureRandom.hex(2)}",
      scopes: 'default'
    ).token
  end

  # Inserts one registry row for `slug` plus the membership for `email`.
  def add_tenant(slug:, email:, status: 'active')
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
  end

  def tenants_from_validate(token)
    post '/api/v1/auth/validate',
         headers: { 'api_access_token' => token, 'Host' => 'localhost' }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)['data']['tenants']
  end

  it 'only exposes the caller own tenant slugs (A never sees B)' do
    user_a = create_user('leak-a')
    user_b = create_user('leak-b')
    add_tenant(slug: 'leak_a', email: user_a.email)
    add_tenant(slug: 'leak_b', email: user_b.email)

    expect(tenants_from_validate(token_for(user_a))).to eq(%w[leak_a])
    expect(tenants_from_validate(token_for(user_b))).to eq(%w[leak_b])
  end

  it 'excludes inactive tenants (fail closed)' do
    user = create_user('leak-inactive')
    add_tenant(slug: 'leak_active', email: user.email)
    add_tenant(slug: 'leak_suspended', email: user.email, status: 'suspended')

    expect(tenants_from_validate(token_for(user))).to eq(%w[leak_active])
  end

  it 'returns an empty list — never a default tenant — without membership' do
    user = create_user('leak-none')
    add_tenant(slug: 'leak_other', email: 'someone-else@example.com')

    expect(tenants_from_validate(token_for(user))).to eq([])
  end

  it 'emits no tenant list at all for an invalid token (401, fail closed)' do
    post '/api/v1/auth/validate',
         headers: { 'api_access_token' => 'not-a-real-token', 'Host' => 'localhost' }

    expect(response).to have_http_status(:unauthorized)
    body = JSON.parse(response.body)
    expect(body.dig('data', 'tenants')).to be_nil
  end

  it 'keeps tenants as a flat string array without schema_name/plan/role' do
    user = create_user('leak-shape')
    add_tenant(slug: 'leak_shape', email: user.email)

    tenants = tenants_from_validate(token_for(user))

    expect(tenants).to eq(%w[leak_shape])
    expect(tenants).to all(be_a(String))
  end
end

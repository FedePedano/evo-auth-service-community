# frozen_string_literal: true

# Creates the multitenant registry tables (`public.tenants` and
# `public.tenant_memberships`) in the test database.
#
# In production these tables live in the shared PostgreSQL database and are
# owned by the CRM service (see
# evo-ai-crm-community/db/migrate/20261001000001_create_tenants_registry.rb).
# The auth service only reads them through qualified `public.*` queries, so the
# auth schema does not declare them. For tests we replicate just enough of the
# schema for `UserTenants.active_slugs_for` / `/validate` to run.
RSpec.configure do |config|
  config.before(:suite) do
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE TABLE IF NOT EXISTS public.tenants (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        slug character varying NOT NULL,
        schema_name character varying NOT NULL,
        status character varying DEFAULT 'active' NOT NULL,
        plan character varying DEFAULT 'free' NOT NULL,
        created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
        updated_at timestamp(6) without time zone NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX IF NOT EXISTS index_tenants_on_slug
        ON public.tenants (slug);
      CREATE UNIQUE INDEX IF NOT EXISTS index_tenants_on_schema_name
        ON public.tenants (schema_name);

      CREATE TABLE IF NOT EXISTS public.tenant_memberships (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        tenant_id uuid NOT NULL REFERENCES public.tenants (id),
        user_id uuid NOT NULL,
        role character varying DEFAULT 'owner' NOT NULL,
        email character varying,
        created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
        updated_at timestamp(6) without time zone NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX IF NOT EXISTS index_tenant_memberships_on_tenant_and_user
        ON public.tenant_memberships (tenant_id, user_id);
      CREATE UNIQUE INDEX IF NOT EXISTS index_tenant_memberships_on_tenant_and_email
        ON public.tenant_memberships (tenant_id, email);
    SQL
  end
end

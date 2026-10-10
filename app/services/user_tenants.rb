# frozen_string_literal: true

# Fase 0.3 (exp/multitenant-a2): resolves the active tenant slugs a user
# belongs to, for the JWT `tenants` claim.
#
# Membership is matched by email (not user_id): CRM users live in each
# tenant's schema and are not reachable by FK from the auth database. The
# registry `public.tenants` and `public.tenant_memberships` are qualified
# explicitly so the lookup does not depend on the connection search_path.
#
# Only tenants with status = 'active' are returned. Any failure (table
# missing in a legacy install, connection error) degrades to [] so token
# emission never breaks.
class UserTenants
  ACTIVE_SLUGS_SQL = <<~SQL.freeze
    SELECT DISTINCT t.slug
    FROM public.tenants t
    JOIN public.tenant_memberships m
      ON m.tenant_id = t.id AND lower(m.email) = $1
    WHERE t.status = 'active'
    ORDER BY t.slug
  SQL

  class << self
    def active_slugs_for(user_or_email)
      email = extract_email(user_or_email)
      return [] if email.blank?

      rows = ActiveRecord::Base.connection.exec_query(
        ACTIVE_SLUGS_SQL, 'user_tenants_active_slugs', [[nil, email]]
      )
      rows.to_a.map { |row| row['slug'] }.compact.uniq
    rescue StandardError => e
      log_warn(e)
      []
    end

    def extract_email(user_or_email)
      value = user_or_email.respond_to?(:email) ? user_or_email.email : user_or_email
      value.to_s.strip.downcase.presence
    end

    private

    def log_warn(error)
      return unless defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger

      Rails.logger.warn("UserTenants: #{error.class} - #{error.message}")
    end
  end
end

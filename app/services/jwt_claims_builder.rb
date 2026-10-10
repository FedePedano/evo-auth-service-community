# frozen_string_literal: true

# Fase 0.3 (exp/multitenant-a2): builds the Doorkeeper JWT payload.
#
# Extracted from the `Doorkeeper::JWT.configure` initializer so the claim
# set is unit-testable. The existing claims are preserved verbatim; the
# only addition is `tenants` (array of active tenant slugs) for users.
# Tokens issued before this change simply lack the `tenants` key, so
# consumers must treat a missing claim as an empty list.
class JwtClaimsBuilder
  class << self
    def build(user:, expires_in:, setup_active: false)
      common = {
        iss: ENV.fetch('DOORKEEPER_JWT_ISS', 'evo-auth-service'),
        aud: ENV.fetch('DOORKEEPER_JWT_AUD', '[]'),
        jti: SecureRandom.uuid,
        iat: Time.current.utc.to_i,
        exp: expires_in.seconds.from_now.to_i
      }

      return common.merge(setup_active: setup_active) unless user

      common.merge(
        sub: user.id.to_s,
        email: user.email,
        name: user.name,
        type: user.type,
        role: user.role_data,
        setup_active: setup_active,
        tenants: UserTenants.active_slugs_for(user)
      )
    end
  end
end

# frozen_string_literal: true

begin
  require 'rails_helper'
rescue LoadError
  RSpec.describe 'AuthHelper#allowed_host?/#allowed_origin?' do
    it 'has spec scaffold ready' do
      skip 'rails_helper is not available in this workspace snapshot'
    end
  end
end

return unless defined?(Rails)

RSpec.describe AuthHelper, 'host/origin allowlist' do
  let(:dummy_class) do
    Class.new do
      include AuthHelper
      attr_accessor :request
    end
  end
  let(:instance) { dummy_class.new }

  def with_env(hosts: nil, origins: nil, cors: nil, frontend: nil)
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('AUTH_ALLOWED_HOSTS', '').and_return(hosts.to_s)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('AUTH_ALLOWED_ORIGINS').and_return(origins)
    allow(ENV).to receive(:[]).with('CORS_ORIGINS').and_return(cors)
    allow(ENV).to receive(:[]).with('FRONTEND_URL').and_return(frontend)
  end

  describe '#allowed_host?' do
    context 'when AUTH_ALLOWED_HOSTS is blank (backward compatible)' do
      it 'allows any host' do
        with_env(hosts: nil)
        expect(instance.allowed_host?('anything.example.com')).to be(true)
      end
    end

    context 'with an explicit allowlist' do
      it 'allows an exact host match' do
        with_env(hosts: 'beexa-auth.evonectech.com')
        expect(instance.allowed_host?('beexa-auth.evonectech.com')).to be(true)
      end

      it 'rejects a host not in the list' do
        with_env(hosts: 'beexa-auth.evonectech.com')
        expect(instance.allowed_host?('evil.example.com')).to be(false)
      end

      it 'is case-insensitive and strips the port' do
        with_env(hosts: 'beexa-auth.evonectech.com')
        expect(instance.allowed_host?('BEEXA-AUTH.Evonectech.com:3001')).to be(true)
      end

      it 'supports multiple comma-separated hosts (internal + public)' do
        with_env(hosts: 'beexa-auth.evonectech.com, evo-auth')
        expect(instance.allowed_host?('evo-auth')).to be(true)
        expect(instance.allowed_host?('beexa-auth.evonectech.com')).to be(true)
        expect(instance.allowed_host?('other')).to be(false)
      end

      it 'supports a leading "*." wildcard for subdomains only' do
        with_env(hosts: '*.evonectech.com')
        expect(instance.allowed_host?('beexa-auth.evonectech.com')).to be(true)
        expect(instance.allowed_host?('a.b.evonectech.com')).to be(true)
        expect(instance.allowed_host?('evonectech.com')).to be(false)
        expect(instance.allowed_host?('notevonectech.com')).to be(false)
      end

      it 'allows everything when "*" is present' do
        with_env(hosts: '*')
        expect(instance.allowed_host?('anything.example.com')).to be(true)
      end
    end
  end

  describe '#allowed_origin?' do
    context 'when no origin allowlist is configured' do
      it 'allows any origin' do
        with_env(hosts: 'x', origins: nil, cors: nil, frontend: nil)
        expect(instance.allowed_origin?('https://evil.example.com')).to be(true)
      end
    end

    context 'with an explicit AUTH_ALLOWED_ORIGINS' do
      it 'accepts an exact origin and rejects others' do
        with_env(origins: 'https://beexa.evonectech.com')
        expect(instance.allowed_origin?('https://beexa.evonectech.com')).to be(true)
        expect(instance.allowed_origin?('https://evil.example.com')).to be(false)
      end

      it 'normalizes case and trailing slash' do
        with_env(origins: 'https://beexa.evonectech.com')
        expect(instance.allowed_origin?('https://BEEXA.evonectech.com/')).to be(true)
      end

      it 'always allows a blank origin (server-to-server)' do
        with_env(origins: 'https://beexa.evonectech.com')
        expect(instance.allowed_origin?(nil)).to be(true)
        expect(instance.allowed_origin?('')).to be(true)
      end

      it 'rejects the literal "null" origin' do
        with_env(origins: 'https://beexa.evonectech.com')
        expect(instance.allowed_origin?('null')).to be(false)
      end
    end

    context 'fallbacks' do
      it 'uses CORS_ORIGINS when AUTH_ALLOWED_ORIGINS is unset' do
        with_env(origins: nil, cors: 'https://beexa.evonectech.com,https://beexa-api-crm.evonectech.com')
        expect(instance.allowed_origin?('https://beexa-api-crm.evonectech.com')).to be(true)
        expect(instance.allowed_origin?('https://evil.example.com')).to be(false)
      end

      it 'uses FRONTEND_URL as last resort' do
        with_env(origins: nil, cors: nil, frontend: 'https://beexa.evonectech.com')
        expect(instance.allowed_origin?('https://beexa.evonectech.com')).to be(true)
      end

      it 'allows everything when "*" is present' do
        with_env(origins: '*')
        expect(instance.allowed_origin?('https://evil.example.com')).to be(true)
      end
    end
  end
end

# frozen_string_literal: true

require "spec_helper"

describe Decidim::Suomifi::Engine do
  # Some of the tests may be causing the Devise OmniAuth strategies to be
  # reconfigured in which case the strategy option information is lost in the
  # Devise configurations. In case the strategy is lost, re-initialize it
  # manually. Normally this is done when the application's middleware stack is
  # loaded.
  after do
    unless ::Devise.omniauth_configs[:suomifi].strategy
      ::OmniAuth::Strategies::Suomifi.new(
        Rails.application,
        Decidim::Suomifi.omniauth_settings
      ) do |strategy|
        ::Devise.omniauth_configs[:suomifi].strategy = strategy
      end
    end
  end

  it "mounts the routes to the core engine" do
    routes = double
    expect(Decidim::Core::Engine).to receive(:routes).and_return(routes)
    expect(routes).to receive(:prepend) do |&block|
      context = double
      expect(context).to receive(:mount).with(described_class => "/")
      context.instance_eval(&block)
    end

    run_initializer("decidim_suomifi.mount_routes")
  end

  it "adds the correct callback and passthru routes to the core engine" do
    run_initializer("decidim_suomifi.mount_routes")

    %w(GET POST).each do |method|
      expect(
        Decidim::Core::Engine.routes.recognize_path(
          "/users/auth/suomifi",
          method: method
        )
      ).to eq(
        controller: "decidim/suomifi/omniauth_callbacks",
        action: "passthru"
      )
      expect(
        Decidim::Core::Engine.routes.recognize_path(
          "/users/auth/suomifi/callback",
          method: method
        )
      ).to eq(
        controller: "decidim/suomifi/omniauth_callbacks",
        action: "suomifi"
      )
    end
  end

  it "adds the correct sign out routes to the core engine" do
    %w(GET POST).each do |method|
      expect(
        Decidim::Core::Engine.routes.recognize_path(
          "/users/auth/suomifi/slo",
          method: method
        )
      ).to eq(
        controller: "decidim/suomifi/sessions",
        action: "slo"
      )
      expect(
        Decidim::Core::Engine.routes.recognize_path(
          "/users/auth/suomifi/spslo",
          method: method
        )
      ).to eq(
        controller: "decidim/suomifi/sessions",
        action: "spslo"
      )
    end
    %w(DELETE POST).each do |method|
      expect(
        Decidim::Core::Engine.routes.recognize_path(
          "/users/sign_out",
          method: method
        )
      ).to eq(
        controller: "decidim/suomifi/sessions",
        action: "destroy"
      )
    end

    expect(
      Decidim::Core::Engine.routes.recognize_path(
        "/users/slo_callback",
        method: "GET"
      )
    ).to eq(
      controller: "decidim/suomifi/sessions",
      action: "slo_callback"
    )
  end

  it "configures the Suomi.fi omniauth strategy for Devise" do
    expect(Devise).to receive(:setup) do |&block|
      cs = Decidim::Suomifi::Test::Runtime.cert_store

      config = double
      expect(config).to receive(:omniauth).with(
        :suomifi,
        mode: :test,
        scope_of_data: :medium_extensive,
        sp_entity_id: "http://1.lvh.me/users/auth/suomifi/metadata",
        certificate: cs.certificate.to_pem,
        private_key: cs.private_key.to_pem,
        assertion_consumer_service_url: "http://1.lvh.me/users/auth/suomifi/callback",
        idp_cert_multi: {
          signing: [cs.sign_certificate.to_pem]
        },
        idp_slo_session_destroy: instance_of(Proc)
      )
      block.call(config)
    end

    run_initializer("decidim_suomifi.setup")
  end

  it "configures the OmniAuth failure app" do
    expect(OmniAuth.config).to receive(:on_failure=) do |proc|
      env = double
      action = double
      expect(env).to receive(:[]).with("PATH_INFO").and_return(
        "/users/auth/suomifi"
      )
      expect(env).to receive(:[]=).with("devise.mapping", ::Devise.mappings[:user])
      expect(Decidim::Suomifi::OmniauthCallbacksController).to receive(
        :action
      ).with(:failure).and_return(action)
      expect(action).to receive(:call).with(env)

      proc.call(env)
    end

    run_initializer("decidim_suomifi.setup")
  end

  it "falls back on the default OmniAuth failure app" do
    failure_app = double

    expect(OmniAuth.config).to receive(:on_failure).and_return(failure_app)
    expect(OmniAuth.config).to receive(:on_failure=) do |proc|
      env = double
      expect(env).to receive(:[]).with("PATH_INFO").and_return(
        "/something/else"
      )
      expect(failure_app).to receive(:call).with(env)

      proc.call(env)
    end

    run_initializer("decidim_suomifi.setup")
  end

  it "adds the mail interceptor" do
    expect(ActionMailer::Base).to receive(:register_interceptor).with(
      Decidim::Suomifi::MailInterceptors::GeneratedRecipientsInterceptor
    )

    run_initializer("decidim_suomifi.mail_interceptors")
  end

  def run_initializer(initializer_name)
    config = described_class.initializers.find do |i|
      i.name == initializer_name
    end
    config.run
  end
end

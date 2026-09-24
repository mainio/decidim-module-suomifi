# Decidim::Suomifi

[![Build Status](https://github.com/mainio/decidim-module-suomifi/actions/workflows/ci_suomifi.yml/badge.svg)](https://github.com/mainio/decidim-module-suomifi/actions)
[![codecov](https://codecov.io/gh/mainio/decidim-module-suomifi/branch/master/graph/badge.svg)](https://codecov.io/gh/mainio/decidim-module-suomifi)

A [Decidim](https://github.com/decidim/decidim) module to add Suomi.fi
strong authentication to Decidim as a way to authenticate and authorize the
users.

The gem has been developed by [Mainio Tech](https://www.mainiotech.fi/).

The development has been sponsored by the
[City of Helsinki](https://www.hel.fi/).

The Population Register Centre (VRK) or the Suomi.fi maintainers are not related
to this gem in any way, nor do they provide technical support for it. Please
contact the gem maintainers in case you find any issues with it.

## Preparation

Please refer to the
[`omniauth-suomifi`](https://github.com/mainio/omniauth-suomifi) documentation
in order to learn more about the preparation and getting started with Suomi.fi.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "decidim-suomifi"
```

And then execute:

```bash
$ bundle
$ bundle exec rails decidim_suomifi:install:migrations
$ bundle exec rails db:migrate
```

After installation, you can add the initializer running the following command:

```bash
$ bundle exec rails generate decidim:suomifi:install
```

You need to set the following configuration options inside the initializer:

- `:scope_of_data` - The scope of data for Suomi.fi
  * Default: `:medium_extensive`
  * `:limited` - Limited scope (name and personal identity number)
  * `:medium_extensive` - Medium extensive scope (limted + address information)
  * `:extensive` - Extensive scope (medium extensive + Finnish citizenship
    information)
- `:sp_entity_id` - The service provider entity ID, i.e. your applications
  entity ID used to identify the service at the Suomi.fi SAML identity provider.
  * Set this to the same ID that you use for the metadata sent to Suomi.fi.
  * Default: depends on the application's URL, e.g.
    `https://www.example.org/users/auth/suomifi/metadata`
- `:certificate_file` - Path to the local certificate included in the metadata
  sent to Suomi.fi.
- `:private_key_file` - Path to the local private key (corresponding to the
  certificate). Will be used to decrypt messages coming from Suomi.fi.

Optionally you can also configure the module with the following options:

- `:auto_email_domain` - Defines the auto-email domain in case the user's domain
  is not stored at Suomi.fi. In case this is not set (default), emails will not
  be auto-generated and users will need to enter them manually in case Suomi.fi
  does not report them.
  * The auto-generated email format is similar to the following string:
    `suomifi-756be91097ac490961fd04f121cb9550@example.org`. The email will
    always have the `suomifi-` prefix and the domain part is defined by the
    configuration option.
  * In case this is not defined, the organization's host will be used as the
    default.
- `:use_suomifi_email` - Defines whether the emails stored in Suomi.fi should
  be used for the user accounts if they are available. Note that not all people
  have an email address stored in the Suomi.fi database and not everyone keeps
  it up to date. Another problem with this is that some people may have an old
  or incorrectly written email address stored in Suomi.fi that may cause wrong
  email addresses to be used for the use accounts.

For more information about these options and possible other options, please
refer to the [`omniauth-suomifi`](https://github.com/mainio/omniauth-suomifi)
documentation.

Note that you will also need to generate a private key and a corresponding
certificate and configure them inside the generated initializer. For the testing
environment you can create a self signed certificate e.g. with the following
command:

```bash
$ mkdir config/cert
$ cd config/cert
$ openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 \
  -keyout suomifi.key -out suomifi.crt
```

For the production environment you will need an actual certificate signed by
a trusted CA. The self signed certificate can be used for the Suomi.fi test
environment.

The install generator will also enable the Suomi.fi authentication method for
OmniAuth by default by adding these lines your `config/secrets.yml`:

```yml
default: &default
  # ...
  omniauth:
    # ...
    suomifi:
      enabled: false
      icon: icon-globe
development:
  # ...
  omniauth:
    # ...
    suomifi:
      enabled: true
      mode: test
      icon: icon-globe
```

This will enable the Suomi.fi authentication for the development environment
only. In case you want to enable it for other environments as well, apply the
OmniAuth configuration keys accordingly to other environments as well.

The development environment is hooking into the Suomi.fi testing endpoints by
default which is defined by the `mode: test` option in the OmniAuth
configuration. For environments that you want to hook into the Suomi.fi
production environment, you can omit this configuration option completely.

The example configuration will set the `icon-globe` icon for the the authentication
button from the Decidim's own iconset. In case you want to have a better and
more formal styling for the sign in button, you will need to customize the sign
in / sign up views.

## Usage

After the installation steps, you will need to enable the Suomi.fi authorization
from Decidim's system management panel. After enabled, you can start using it.

This gem also provides a Suomi.fi sign in method which will automatically
authorize the user accounts. In case the users already have an account, they
can still authorize themselves using the Suomi.fi authorization.

## Customization

For some specific needs, you may need to store extra metadata for the Suomi.fi
authorization or add new authorization configuration options for the
authorization.

This can be achieved by applying the following configuration to the module
inside the initializer described above:

```ruby
# config/initializers/suomifi.rb

Decidim::Suomifi.configure do |config|
  # ... keep the default configuration as is ...
  # Add this extra configuration:
  config.workflow_configurator = lambda do |workflow|
    # When expiration is set to 0 minutes, it will never expire.
    workflow.expires_in = 0.minutes
    workflow.action_authorizer = "CustomSuomifiActionAuthorizer"
    workflow.options do |options|
      options.attribute :custom_option, type: :string, required: false
    end
  end
  config.metadata_collector_class = CustomSuomifiMetadataCollector
end
```

For the workflow configuration options, please refer to the
[decidim-verifications documentation](https://github.com/decidim/decidim/tree/master/decidim-verifications).

For the custom metadata collector, please extend the default class as follows:

```ruby
# frozen_string_literal: true

class CustomSuomifiMetadataCollector < Decidim::Suomifi::Verification::MetadataCollector
  def metadata
    base = super

    base.tap do |data|
      # You can access the SAML attributes using the `saml_attributes` accessor:
      postal_code = saml_attributes[:permanent_domestic_address_postal_code]

      # Or you can access the base attributes already defined through the
      # default metadata collector:
      postal_code = base[:postal_code]

      unless postal_code.blank?
        # This will actually add the data to the user's authorization metadata
        # hash.
        data[:extra] = "Custom data for: #{postal_code}"
      end
    end
  end
end
```

## Contributing

See [Decidim](https://github.com/decidim/decidim).

### Testing

To run the tests run the following in the gem development path:

```bash
$ bundle
$ DATABASE_USERNAME=<username> DATABASE_PASSWORD=<password> bundle exec rake test_app
$ DATABASE_USERNAME=<username> DATABASE_PASSWORD=<password> bundle exec rspec
```

Note that the database user has to have rights to create and drop a database in
order to create the dummy test app database.

In case you are using [rbenv](https://github.com/rbenv/rbenv) and have the
[rbenv-vars](https://github.com/rbenv/rbenv-vars) plugin installed for it, you
can add these environment variables to the root directory of the project in a
file named `.rbenv-vars`. In this case, you can omit defining these in the
commands shown above.

### Test code coverage

If you want to generate the code coverage report for the tests, you can use
the `SIMPLECOV=1` environment variable in the rspec command as follows:

```bash
$ SIMPLECOV=1 bundle exec rspec
```

This will generate a folder named `coverage` in the project root which contains
the code coverage report.

### Localization

If you would like to see this module in your own language, you can help with its
translation at Crowdin:

https://crowdin.com/project/decidim-suomifi

## License

See [LICENSE-AGPLv3.txt](LICENSE-AGPLv3.txt).

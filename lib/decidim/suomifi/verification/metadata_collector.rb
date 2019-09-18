# frozen_string_literal: true

module Decidim
  module Suomifi
    module Verification
      class MetadataCollector
        def initialize(saml_attributes)
          @saml_attributes = saml_attributes
        end

        def metadata
          hetu = Henkilotunnus::Hetu.new(
            saml_attributes[:national_identification_number]
          )
          # In case the HETU was not sent by Suomi.fi, it will be empty and
          # therefore invalid and will not have the gender information. With
          # empty HETU, `Henkilotunnus::Hetu` would otherwise report "female" as
          # the gender which would not be correct.
          gender = nil
          date_of_birth = nil

          # Note that we cannot call hetu.valid? because it will also call
          # `:valid_person_number?`. This checks that the HETU is in range
          # 002-899 which are the actual HETU codes stored in the population
          # register system. The numbers above 899 are temporary codes, e.g. in
          # situations when a person does not yet have a HETU. Temporary codes
          # may be returned by the Suomi.fi endpoint e.g. in the testing mode.
          # Regarding the information needs here, it does not matter whether the
          # HETU is temporary or permanent.
          valid_hetu = hetu.send(:valid_format?) && hetu.send(:valid_checksum?)
          if valid_hetu
            gender = hetu.male? ? "m" : "f"
            # `.to_s` returns an ISO 8601 formatted string (YYYY-MM-DD for dates)
            date_of_birth = hetu.date_of_birth.to_s
          elsif saml_attributes[:eidas_date_of_birth]
            # xsd:date (YYYY-MM_DD)
            date_of_birth = saml_attributes[:eidas_date_of_birth]
          end

          postal_code_permanent = true
          postal_code = saml_attributes[:permanent_domestic_address_postal_code]
          unless postal_code
            postal_code_permanent = false
            postal_code = saml_attributes[:temporary_domestic_address_postal_code]
          end

          first_name = saml_attributes[:first_names]
          last_name = saml_attributes[:last_name]
          given_name = saml_attributes[:given_name]

          eidas = false
          if saml_attributes[:eidas_person_identifier]
            eidas = true
            first_name = saml_attributes[:eidas_first_names]
            last_name = saml_attributes[:eidas_family_name]
          end

          {
            eidas: eidas,
            gender: gender,
            date_of_birth: date_of_birth,
            pin_digest: person_identifier_digest,
            # The first name will contain all first names of the person
            first_name: first_name,
            # The given name is the primary first name of the person, also known
            # as "calling name" (kutsumanimi).
            given_name: given_name,
            last_name: last_name,
            # The municipality number, see:
            # http://tilastokeskus.fi/meta/luokitukset/kunta/001-2017/index.html
            municipality: saml_attributes[:home_municipality_number],
            municipality_name: saml_attributes[:home_municipality_name_fi],
            postal_code: postal_code,
            permanent_address: postal_code_permanent
          }
        end

        # Digested format of the person's identifier unique to the person. The
        # digested format is used because the undigested format may hold
        # personal sensitive information about the user and may require special
        # care regarding the privacy policy. These will still be unique hashes
        # bound to the person's identification number.
        def person_identifier_digest
          @person_identifier_digest ||= begin
            prefix = nil
            pin = nil

            if saml_attributes[:national_identification_number]
              prefix = "FI"
              pin = saml_attributes[:national_identification_number]
            elsif saml_attributes[:eidas_person_identifier]
              prefix = "EIDAS"
              pin = saml_attributes[:eidas_person_identifier]
            end

            if prefix && pin
              Digest::MD5.hexdigest(
                "#{prefix}:#{pin}:#{Rails.application.secrets.secret_key_base}"
              )
            end
          end
        end

        protected

        attr_reader :saml_attributes
      end
    end
  end
end

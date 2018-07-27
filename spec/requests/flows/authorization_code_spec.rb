require 'spec_helper_integration'

feature 'Authorization Code Flow' do
  background do
    config_is_set(:authenticate_resource_owner) { User.first || redirect_to('/sign_in') }
    client_exists
    create_resource_owner
    sign_in
  end

  scenario 'resource owner authorizes the client' do
    visit authorization_endpoint_url(client: @client)
    click_on 'Authorize'

    access_grant_should_exist_for(@client, @resource_owner)

    i_should_be_on_client_callback(@client)

    url_should_have_param('code', Doorkeeper::AccessGrant.first.token)
    url_should_not_have_param('state')
    url_should_not_have_param('error')
  end

  scenario 'resource owner authorizes using test url' do
    @client.redirect_uri = Doorkeeper.configuration.native_redirect_uri
    @client.save!
    visit authorization_endpoint_url(client: @client)
    click_on 'Authorize'

    access_grant_should_exist_for(@client, @resource_owner)

    url_should_have_param('code', Doorkeeper::AccessGrant.first.token)
    i_should_see 'Authorization code:'
    i_should_see Doorkeeper::AccessGrant.first.token
  end

  scenario 'resource owner authorizes the client with state parameter set' do
    visit authorization_endpoint_url(client: @client, state: 'return-me')
    click_on 'Authorize'
    url_should_have_param('code', Doorkeeper::AccessGrant.first.token)
    url_should_have_param('state', 'return-me')
    url_should_not_have_param('code_challenge_method')
  end

  scenario 'resource owner requests an access token with authorization code' do
    visit authorization_endpoint_url(client: @client)
    click_on 'Authorize'

    authorization_code = Doorkeeper::AccessGrant.first.token
    create_access_token authorization_code, @client

    access_token_should_exist_for(@client, @resource_owner)

    should_not_have_json 'error'

    should_have_json 'access_token', Doorkeeper::AccessToken.first.token
    should_have_json 'token_type', 'bearer'
    should_have_json_within 'expires_in', Doorkeeper::AccessToken.first.expires_in, 1
  end

  context 'with PKCE' do
    scenario 'resource owner authorizes the client with code_challenge parameter set' do
      code_verifier = 'a45a9fea-0676-477e-95b1-a40f72ac3cfb'
      visit pkce_authorization_endpoint_url(client: @client, code_challenge: code_verifier)
      click_on 'Authorize'

      url_should_have_param('code', Doorkeeper::AccessGrant.first.token)
      url_should_not_have_param('code_challenge')
      url_should_not_have_param('code_challenge_method')
    end

    scenario 'resource owner requests an access token with authorization code but not pkce token' do
      visit authorization_endpoint_url(client: @client)
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      code_verifier = SecureRandom.uuid
      create_access_token_with_pkce authorization_code, @client, code_verifier

      should_have_json 'error', 'invalid_grant'
    end

    scenario 'resource owner requests an access token with authorization code and plain code challenge method' do
      code_verifier = 'a45a9fea-0676-477e-95b1-a40f72ac3cfb'

      visit pkce_authorization_endpoint_url(client: @client, code_challenge: code_verifier)
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token_with_pkce authorization_code, @client, code_verifier

      access_token_should_exist_for(@client, @resource_owner)

      should_not_have_json 'error'

      should_have_json 'access_token', Doorkeeper::AccessToken.first.token
      should_have_json 'token_type', 'bearer'
      should_have_json_within 'expires_in', Doorkeeper::AccessToken.first.expires_in, 1
    end

    scenario 'resource owner requests an access token with authorization code and S256 code challenge method' do
      code_verifier = 'a45a9fea-0676-477e-95b1-a40f72ac3cfb'
      challenge = Doorkeeper::AccessGrant.generate_code_challenge(code_verifier)

      visit pkce_authorization_endpoint_url(client: @client,
                                       code_challenge: challenge,
                                       code_challenge_method: 'S256')
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token_with_pkce authorization_code, @client, code_verifier

      access_token_should_exist_for(@client, @resource_owner)

      should_not_have_json 'error'

      should_have_json 'access_token', Doorkeeper::AccessToken.first.token
      should_have_json 'token_type', 'bearer'
      should_have_json_within 'expires_in', Doorkeeper::AccessToken.first.expires_in, 1
    end

    scenario 'resource owner requests an access token with authorization code but no code verifier' do
      code_verifier = 'a45a9fea-0676-477e-95b1-a40f72ac3cfb'
      challenge = Doorkeeper::AccessGrant.generate_code_challenge(code_verifier)

      visit pkce_authorization_endpoint_url(client: @client,
                                       code_challenge: challenge,
                                       code_challenge_method: 'S256')
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token_with_pkce authorization_code, @client

      should_not_have_json 'access_token'
      should_have_json 'error', 'invalid_request'
    end

    scenario 'resource owner requests an access token with authorization code and code_challenge' do
      code_verifier = 'a45a9fea-0676-477e-95b1-a40f72ac3cfb'
      visit pkce_authorization_endpoint_url(client: @client,
                                            code_challenge: code_verifier,
                                            code_challenge_method: 'plain')
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      puts Doorkeeper::AccessGrant.first.inspect
      create_access_token_with_pkce authorization_code, @client, code_verifier: nil

      should_not_have_json 'access_token'
      should_have_json 'error', 'invalid_grant'
    end

    scenario 'resource owner requests an access token with authorization code with wrong verifier' do
      challenge = Doorkeeper::AccessGrant.generate_code_challenge('a45a9fea-0676-477e-95b1-a40f72ac3cfb')
      visit pkce_authorization_endpoint_url(client: @client,
                                       code_challenge: challenge,
                                       code_challenge_method: 'S256')
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token_with_pkce authorization_code, @client, 'incorrect-code-verifier'

      should_not_have_json 'access_token'
      should_have_json 'error', 'invalid_grant'
    end

    scenario 'resource owner requests an access token with authorization code with missing challenge method' do
      challenge = Doorkeeper::AccessGrant.generate_code_challenge('a45a9fea-0676-477e-95b1-a40f72ac3cfb')
      visit pkce_authorization_endpoint_url(client: @client, code_challenge: challenge)
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token_with_pkce authorization_code, @client, 'incorrect-code-verifier'

      should_not_have_json 'access_token'
      should_have_json 'error', 'invalid_grant'
    end
  end

  context 'with scopes' do
    background do
      default_scopes_exist :public
      optional_scopes_exist :write
    end

    scenario 'resource owner authorizes the client with default scopes' do
      visit authorization_endpoint_url(client: @client)
      click_on 'Authorize'
      access_grant_should_exist_for(@client, @resource_owner)
      access_grant_should_have_scopes :public
    end

    scenario 'resource owner authorizes the client with required scopes' do
      visit authorization_endpoint_url(client: @client, scope: 'public write')
      click_on 'Authorize'
      access_grant_should_have_scopes :public, :write
    end

    scenario 'resource owner authorizes the client with required scopes (without defaults)' do
      visit authorization_endpoint_url(client: @client, scope: 'write')
      click_on 'Authorize'
      access_grant_should_have_scopes :write
    end

    scenario 'new access token matches required scopes' do
      visit authorization_endpoint_url(client: @client, scope: 'public write')
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token authorization_code, @client

      access_token_should_exist_for(@client, @resource_owner)
      access_token_should_have_scopes :public, :write
    end

    scenario 'returns new token if scopes have changed' do
      client_is_authorized(@client, @resource_owner, scopes: 'public write')
      visit authorization_endpoint_url(client: @client, scope: 'public')
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token authorization_code, @client

      expect(Doorkeeper::AccessToken.count).to be(2)

      should_have_json 'access_token', Doorkeeper::AccessToken.last.token
    end

    scenario 'resource owner authorizes the client with extra scopes' do
      client_is_authorized(@client, @resource_owner, scopes: 'public')
      visit authorization_endpoint_url(client: @client, scope: 'public write')
      click_on 'Authorize'

      authorization_code = Doorkeeper::AccessGrant.first.token
      create_access_token authorization_code, @client

      expect(Doorkeeper::AccessToken.count).to be(2)

      should_have_json 'access_token', Doorkeeper::AccessToken.last.token
      access_token_should_have_scopes :public, :write
    end
  end
end

describe 'Authorization Code Flow' do
  before do
    Doorkeeper.configure do
      orm DOORKEEPER_ORM
      use_refresh_token
    end
    client_exists
  end

  context 'issuing a refresh token' do
    before do
      authorization_code_exists application: @client
    end

    it 'second of simultaneous client requests get an error for revoked acccess token' do
      authorization_code = Doorkeeper::AccessGrant.first.token
      allow_any_instance_of(Doorkeeper::AccessGrant).to receive(:revoked?).and_return(false, true)

      post token_endpoint_url(code: authorization_code, client: @client)

      should_not_have_json 'access_token'
      should_have_json 'error', 'invalid_grant'
    end
  end
end

define [
  'underscore'
  'cord!isBrowser'
  'cord!utils/Future'
  'cord!errors'
], (_, isBrowser, Future, errors) ->

  class OAuth2

    @inject: ['request', 'config']

    constructor: (options) ->
      @deferredRefreshTokenCallbacks = []
      @refreshTokenRequested = false

      defaultOptions =
        clientId: ''
        secretKey: ''
        endpoints:
          authorize: '/oauth/authorize'
          accessToken: '/oauth/access_token'
      @options = _.extend defaultOptions, options


    grantAccessTokenByAuhorizationCode: (code, scope) ->
      ###
      Получает токены по коду авторизации, ранее выданному авторизационным сервером
      Использует спец. секцию xdrs для отправки запросов с секретными материалами.
      ###
      promise = Future.single('OAuth2::grantAccessTokenByAuthorizationCode promise')
      params =
        grant_type: 'authorization_code'
        code: code
        client_id: @options.clientId
        client_secret: '#{client_secret}'
        format: 'json'
        redirect_uri: @options.endpoints.redirectUri
        scope: scope

      requestUrl = "#{@options.xdrs.protocol}://#{@options.xdrs.host}#{@options.xdrs.urlPrefix}#{@options.endpoints.accessToken}"

      @request.get requestUrl, params, (result) =>
        if result and result.access_token and result.refresh_token
          promise.resolve(result.access_token, result.refresh_token, code)
        else
          promise.reject(new Error('No response from authorization server'))
      promise


    ## Получение токена по grant_type = password (логин и пароль)
    grantAccessTokenByPassword: (user, password, scope, callback) ->
      params =
        grant_type: 'password'
        username: user
        password: password
        client_id: @options.clientId
        scope: scope
        json: true

      @request.get @options.endpoints.accessToken, params, (result) ->
        if result
          callback result.access_token, result.refresh_token
        else
          callback null, null


    ## Получение токена по grant_type = extension (например, одноразовый ключ)
    grantAccessTokenByExtensions: (url, params, scope, callback) ->
      requestParams =
        grant_type: url
        client_id: @options.clientId
        scope: scope
        json: true

      requestParams = _.extend params, requestParams

      @request.get @options.endpoints.accessToken, requestParams, (result) ->
        if result
          callback result.access_token, result.refresh_token
        else
          callback null, null


    grantAccessTokenByRefreshToken: (refreshToken, scope, retries = 1) ->
      ###
      Requests access_token by refresh_token
      @param {String} refreshToken
      @param {String} scope
      @param (optional){Int} retries Number of retries on fail before giving up
      @return {Future[Array[String, String]]} access_token and new refresh_token
      ###
      params =
        grant_type: 'refresh_token'
        refresh_token: refreshToken
        client_id: @options.clientId
        scope: scope

      if not @_refreshTokenRequestPromise
        resultPromise = Future.single('OAuth2::grantAccessTokenByRefreshToken')

        @request.get @options.endpoints.accessToken, params, (result, err) =>
          if result
            if result.error # this means that refresh token is outdated
              resultPromise.resolve [null, null]
            else
              resultPromise.resolve [ result.access_token, result.refresh_token ]
          else if retries > 0
            _console.warn 'Error while refreshing oauth token! Will retry after pause... Error:', err
            Future.timeout(500).then =>
              @_refreshTokenRequestPromise = null
              @grantAccessTokenByRefreshToken(refreshToken, scope, retries - 1)
            .link(resultPromise)
          else
            resultPromise.reject(new Error("Failed to refresh oauth token! Reason: #{JSON.stringify(err)} "))

        @_refreshTokenRequestPromise = resultPromise

      @_refreshTokenRequestPromise


    getAuthCodeWithoutPassword: (scope) ->
      ###
      Try to acquire auth Code. Succeeds only if user has been already logged in.
      Oauth2 server uses it's cookies to identify user
      ###
      promise = Future.single('Api::getAuthCodeWithoutPassword promise')
      if not isBrowser
        promise.reject(new Error('It is only possible to get auth code at client side'))
      else
        params =
          response_type: 'code'
          client_id: @config.oauth2.clientId
          scope: scope
          format: 'json'
          xhrOptions:
            withCredentials: true

        requestUrl = @config.oauth2.endpoints.authCodeWithoutLogin
        if not requestUrl
          return promise.reject('config.oauth2.endpoints.authCodeWithoutLogin parameter is required')
        @request.get requestUrl, params, (response, error) ->
          if response.code
            promise.resolve(response.code)
          else
            promise.reject(new errors.MegaIdAuthFailed('No auth code recieved. Response: ' + JSON.stringify(response) + JSON.stringify(error)))
      promise


    getAuthCodeByPassword: (login, password, scope) ->
      promise = Future.single('Api::getAuthCodeByPassword promise')
      if !isBrowser
        promise.reject(new Error('It is only possible to get auth code at client side'))
      else
        params =
          response_type: 'code'
          client_id: @config.oauth2.clientId
          login: login
          password: password
          format: 'json'
          scope: scope
          xhrOptions:
            withCredentials: true

        requestUrl = @config.oauth2.endpoints.authCode
        @request.get requestUrl, params, (response, error) ->
          if response and response.code
            promise.resolve(response.code)
          else
            promise.reject(new errors.MegaIdAuthFailed('No auth code recieved. Response:'+ JSON.stringify(response) + JSON.stringify(error)))
      promise


    grantAccessTokenByMegaId: (code, scope) ->
      ###
      Grant access token from backend, using Code accuired from MegaplanId on front-end
      Refreshing access tokens done via grantAccessTokenByRefreshToken
      ###
      promise = Future.single('OAuth2::grantAccessTokenByMegaId promise')
      params =
        grant_type: 'authorization_code'
        code: code
        scope: scope

      requestUrl = @options.endpoints.accessToken

      @request.get requestUrl, params, (result) =>
        if result and result.access_token and result.refresh_token
          promise.resolve(result.access_token, result.refresh_token, code)
        else
          promise.reject(new Error('No response from backend server (MegaId)'))
      promise


    grantAccessTokenByInviteCode: (inviteCode, code, scope) ->
      ###
      Convert invite auth into MegaplanId auth, and grant access tokes
      ###

      promise = Future.single('OAuth2::grantAccessTokenByInviteCode promise')
      params =
        megaplan_start_invite: inviteCode
        code: code
        scope: scope

      requestUrl = @options.endpoints.inviteCode

      @request.get requestUrl, params, (result) =>
        if result and result.access_token and result.refresh_token
          promise.resolve(result.access_token, result.refresh_token, code)
        else
          promise.reject(new Error(if _.isObject(result) and result.error then result.error else JSON.stringify(result)))
      promise


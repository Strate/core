define [
  'jquery.cookie'
  'underscore'
], ($, _) ->

  class BrowserCookie

# TODO: PHONEGAP
    cookies: {}


    get: (name, defaultValue) ->
      @cookies[name] ? $.cookie(name) ? defaultValue


    set: (name, value, params) =>
      _params =
        path: '/'

      _params = _.extend _params, params if params

      @cookies[name] = value
      $.cookie(name, value, _params)

      true

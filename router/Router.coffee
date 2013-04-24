define ['underscore'], (_) ->

  class Router

    path: ''

    constructor: ->
      @routes = []

    addRoutes: (routes) ->
      for path, definition of routes
        @routes.push(new Route(path, definition))

    setDefWidget: (defWidget) ->
      @defWidget = defWidget

    matchRoute: (path, options) ->
      for route in @routes
        if route.match(path, options)
          return route

    setPath: (path) ->
      @path = path

    getPath: ->
      path = @path
      #      path = window.location.pathname
      if path.substr(0,1) isnt '/'
        path = '/' + path
      path.match(/[^#?\s]+/)[0] || '/'

#    @add: (path, callback) ->
#      if (typeof path is 'object' and path not instanceof RegExp)
#        @add(key, value) for key, value of path
#      else
#        @routes.push(new @(path, callback))


  namedParam = /:([\w\d]+)/g
  splatParam = /\*([\w\d]+)/g
  escapeRegExp = /[-[\]{}()+?.,\\^$|#\s]/g

  class Route

    constructor: (@path, @definition) ->
      @widget         = @definition.widget ? null
      @params         = @definition.params ? {}
      @regexp         = @definition.regexp ? false

      path = new RegExp path if @regexp

      @names = []

      if typeof path is 'string'
        namedParam.lastIndex = 0
        while (match = namedParam.exec(path)) != null
          @names.push(match[1])

        splatParam.lastIndex = 0
        while (match = splatParam.exec(path)) != null
          @names.push(match[1])

        path = path.replace(escapeRegExp, '\\$&')
                   .replace(namedParam, '([^\/]*)')
                   .replace(splatParam, '(.*?)')

        @route = new RegExp('^' + path + '$')
      else
        @route = path

    match: (path, options = {}) ->
      match = @route.exec(path)
      return false unless match
      options.match = match
      params = match.slice(1)

      if @names.length
        for param, i in params
          options[@names[i]] = param

      @params = _.extend(@params, options)
#      @params = options

      true
#      @callback.call(null, options) isnt false


  Router

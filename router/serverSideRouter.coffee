define [
  'cord!AppConfigLoader'
  'cord!router/Router'
  'cord!ServiceContainer'
  'cord!WidgetRepo'
  'underscore'
  'url'
], (AppConfigLoader, Router, ServiceContainer, WidgetRepo, _, url) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse(req.url, true)

      @currentPath = req.url

      if (routeInfo = @matchRoute(path.pathname))

        rootWidgetPath = routeInfo.route.widget
        routeCallback = routeInfo.route.callback
        params = _.extend(path.query, routeInfo.params)

        serviceContainer = new ServiceContainer
        serviceContainer.set 'container', serviceContainer

        ###
          Другого места получить из первых рук запрос-ответ нет
        ###

        serviceContainer.set 'serverRequest', req
        serviceContainer.set 'serverResponse', res

        ###
          Конфиги
        ###
        global.appConfig.browser.calculateByRequest?(req)
        global.appConfig.node.calculateByRequest?(req)

        widgetRepo = new WidgetRepo

        clear = =>
          if serviceContainer?
            serviceContainer.eval 'oauth2', (oauth2) =>
              oauth2.clear()

          serviceContainer = null
          widgetRepo = null

        config = global.config
        config.api.getUserPasswordCallback = (callback) ->
          if serviceContainer
            response = serviceContainer.get 'serverResponse'
            request = serviceContainer.get 'serverRequest'
            if !response.alreadyRelocated
              response.shouldKeepAlive = false
              response.alreadyRelocated = true
              response.writeHead 302,
                "Location": '/user/login/?back=' + request.url
                "Cache-Control" : "no-cache, no-store, must-revalidate"
                "Pragma": "no-cache"
                "Expires": 0
              response.end()
              clear()

        serviceContainer.set 'config', config

        serviceContainer.set 'widgetRepo', widgetRepo
        widgetRepo.setServiceContainer(serviceContainer)

        widgetRepo.setRequest(req)
        widgetRepo.setResponse(res)

        AppConfigLoader.ready().done (appConfig) ->
          for serviceName, info of appConfig.services
            do (info) ->
              serviceContainer.def serviceName, info.deps, (get, done) ->
                info.factory.call(serviceContainer, get, done)

          if rootWidgetPath?
            widgetRepo.createWidget rootWidgetPath, (rootWidget) ->
              rootWidget._isExtended = true
              widgetRepo.setRootWidget(rootWidget)
              rootWidget.show params, (err, output) ->
                if err then throw err
                #prevent browser to use the same connection
                res.shouldKeepAlive = false
                res.writeHead 200, 'Content-Type': 'text/html'
                res.end(output)
                # todo: may be need some cleanup before?
                clear()
          else if routeCallback?
            routeCallback
              serviceContainer: serviceContainer
              params: params
            , =>
              res.end()
              clear()
          else
            res.shouldKeepAlive = false
            res.writeHead 404, 'Content-Type': 'text/html'
            res.end 'Error 404'
            clear()
        true
      else
        false



  new ServerSideRouter

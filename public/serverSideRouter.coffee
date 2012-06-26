`if (typeof define !== 'function') { var define = require('amdefine')(module) }`

define [
  'url'
  './widgetInitializer'
  './Router'
], (url, widgetInitializer, Router) ->

  class ServerSideRouter extends Router

    process: (req, res) ->
      path = url.parse req.url
      console.log "router.process #{ req.url } #{ path.pathname }"

      if (route = @matchRoute path.pathname)
        rootWidgetPath = route.widget
        action = route.action
        params = route.params

        res.writeHead 200, {'Content-Type': 'text/html'}

        RootWidgetClass = require(rootWidgetPath);
        rootWidget = new RootWidgetClass;
        widgetInitializer.setRootWidget rootWidget

        rootWidget.showAction action, params, (err, output) ->
          if err then throw err
          res.end output

        true
      else
        false


  new ServerSideRouter
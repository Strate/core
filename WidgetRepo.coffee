define [
  'postal'
  'cord!deferAggregator'
  'underscore'
], (postal, deferAggregator, _) ->

  class WidgetRepo
    widgets: {}

    rootWidget: null

    _loadingCount: 0

    _initEnd: false

    _widgetOrder: []

    _pushBindings: {}

    _currentExtendList: []
    _newExtendList: []

    createWidget: () ->
      ###
      Main widget factory.
      All widgets should be created through this call.

      @param String path canonical path of the widget
      @param (optional)String contextBundle calling context bundle to expand relative widget paths
      @param Callback(Widget) callback callback in which resulting widget will be passed as argument
      ###

      # normalizing arguments
      path = arguments[0]
      if _.isFunction arguments[1]
        callback = arguments[1]
        contextBundle = null
      else if _.isFunction arguments[2]
        callback = arguments[2]
        contextBundle = arguments[1]
      else
        throw "Callback should be passed to the widget factory!"

      bundleSpec = if contextBundle then "@#{ contextBundle }" else ''

      require ["cord-w!#{ path }#{ bundleSpec }"], (WidgetClass) =>
        widget = new WidgetClass
          repo: this

        @widgets[widget.ctx.id] =
          widget: widget

        callback widget

#      , (err) ->
#        failedId = if err.requireModules? then err.requireModules[0] else null
#        console.log failedId
#        console.log err
#        if failedId == "cord-w!#{ path }#{ bundleSpec }"
#          console.log "found"
#          requirejs.undef failedId
#          require [failedId], ->
#            null
#          , (err) ->
#            console.log "error again", err


    dropWidget: (id) ->
      if @widgets[id]?
        console.log "drop widget #{ @widgets[id].widget.constructor.name }(#{id})"
        @widgets[id].widget.clean()
        @widgets[id].widget = null
        delete @widgets[id]
      else
        throw "Try to drop unknown widget with id = #{ id }"


    registerParent: (childWidget, parentWidget) ->
      ###
      Register child-parent relationship in the repo
      ###
      info = @widgets[childWidget.ctx.id]
      if info.parent?
        info.parent.unbindChild childWidget
      info.parent = parentWidget

    setRootWidget: (widget) ->
      info = @widgets[widget.ctx.id]
      if info.parent?
        info.parent.unbindChild widget
      info.parent = null
      @rootWidget = widget

    getTemplateCode: ->
      """
      <script data-main="/bundles/cord/core/browserInit" src="/vendor/requirejs/require.js"></script>
      <script>
          function cordcorewidgetinitializerbrowser(wi) {
            #{ @rootWidget.getInitCode() }
            wi.endInit();
          };
      </script>
      """

    getTemplateCss: ->
      """
        #{ @rootWidget.getInitCss() }
      """

    endInit: ->
      @_initEnd = true

    ##
     #
     # @browser-only
     ##
    init: (widgetPath, ctx, namedChilds, childBindings, isExtended, parentId) ->
      @_loadingCount++
      @_widgetOrder.push ctx.id

      for widgetId, bindingMap of childBindings
        @_pushBindings[widgetId] = {}
        for ctxName, paramName of bindingMap
          @_pushBindings[widgetId][ctxName] = paramName

      require ["cord-w!#{ widgetPath }"], (WidgetClass) =>
        widget = new WidgetClass
          context: ctx
          repo: this
          extended: isExtended

        widget._isExtended = isExtended

        if @_pushBindings[ctx.id]?
          for ctxName, paramName of @_pushBindings[ctx.id]
            #console.log "#{ paramName }=\"^#{ ctxName }\" for #{ ctx.id }"
            @subscribePushBinding parentId, ctxName, widget, paramName

        @widgets[ctx.id] =
          widget: widget
          namedChilds: namedChilds

        completeFunc = =>
          @_loadingCount--
          if @_loadingCount == 0 and @_initEnd
            @setupBindings()

        if parentId?
          retryCounter = 0
          timeoutFunc = =>
            if @widgets[parentId]?
              @widgets[parentId].widget.registerChild widget, @widgets[parentId].namedChilds[ctx.id] ? null
              completeFunc()
            else if retryCounter < 10
              console.log "widget load timeout activated", retryCounter
              setTimeout timeoutFunc, retryCounter++
            else
              throw "Try to use uninitialized parent widget with id = #{ parentId } - couldn't load parent widget within timeout!"
          timeoutFunc()
        else
          @rootWidget = widget
          completeFunc()


    setupBindings: ->
      # organizing extendList in right order
      for id in @_widgetOrder
        widget = @widgets[id].widget
        if widget._isExtended
          @_currentExtendList.push widget
      # initializing DOM bindings of widgets in reverse order (leafs of widget tree - first)
      @bind(id) for id in @_widgetOrder.reverse()

    bind: (widgetId) ->
      if @widgets[widgetId]?
        @widgets[widgetId].widget.initBehaviour()
      else
        throw "Try to use uninitialized widget with id = #{ widgetId }"


    getById: (id) ->
      ###
      Returns widget with the given id if it is exists.
      Throws exception otherwise.
      @param String id widget id
      @return Widget
      ###

      if @widgets[id]?
        @widgets[id].widget
      else
        throw "Try to get uninitialized widget with id = #{ id }"

    #
    # Subscribes child widget to the parent widget's context variable change event
    #
    # @param String parentWidgetId id of the parent widget
    # @param String ctxName name of parent's context variable whose changes we are listening to
    # @param Widget childWidget subscribing child widget object
    # @param String paramName child widget's default action input param name which should be set to the context variable
    #                         value
    # @return postal subscription object
    #
    subscribePushBinding: (parentWidgetId, ctxName, childWidget, paramName) ->
      subscription = postal.subscribe
        topic: "widget.#{ parentWidgetId }.change.#{ ctxName }"
        callback: (data, envelope) ->
          params = {}

          # param with name "params" is a special case and we should expand the value as key-value pairs
          # of widget's params
          if paramName == 'params'
            if _.isObject data.value
              for subName, subValue of data.value
                params[subName] = subValue
            else
              # todo: warning?
          else
            params[paramName] = data.value

          console.log "(wi) push binding event of parent (#{ envelope.topic }) for child widget #{ childWidget.constructor.name }::#{ childWidget.ctx.id }::#{ paramName } -> #{ data.value }"
          deferAggregator.fireAction childWidget, 'default', params
      childWidget.addSubscription subscription
      subscription


    injectWidget: (widgetPath, action, params) ->
      extendWidget = @findAndCutMatchingExtendWidget widgetPath
#      console.log "current root widget = #{ @rootWidget.constructor.name }"
      _oldRootWidget = @rootWidget
      if extendWidget?
        if _oldRootWidget != extendWidget
          @setRootWidget extendWidget
          extendWidget.getStructTemplate (tmpl) =>
            tmpl.assignWidget tmpl.struct.ownerWidget, extendWidget
            tmpl.replacePlaceholders tmpl.struct.ownerWidget, extendWidget.ctx[':placeholders'], =>
              extendWidget.fireAction action, params
              @dropWidget _oldRootWidget.ctx.id
              @rootWidget.browserInit extendWidget
        else
          extendWidget.fireAction action, params
          #throw 'not supported yet!'
      else
        @createWidget widgetPath, (widget) =>
          @setRootWidget widget
          widget.injectAction action, params, (commonBaseWidget) =>
            @dropWidget _oldRootWidget.ctx.id unless commonBaseWidget == _oldRootWidget
            @rootWidget.browserInit commonBaseWidget

    findAndCutMatchingExtendWidget: (widgetPath) ->
      result = null
      counter = 0
#      console.log "@_currentExtendList = ", @_currentExtendList
      for extendWidget in @_currentExtendList
#        console.log "#{ widgetPath } == #{ extendWidget.getPath() }"
        if widgetPath == extendWidget.getPath()
          found = true
          # removing all extend tree below found widget
          @_currentExtendList.shift() while counter--
          # ... and prepending extend tree with the new widgets
          @_newExtendList.reverse()
          @_currentExtendList.unshift(wdt) for wdt in @_newExtendList
          @_newExtendList = []

          result = extendWidget
          break
        counter++
      result

    registerNewExtendWidget: (widget) ->
      @_newExtendList.push widget

    replaceExtendTree: ->
      @_currentExtendList = @_newExtendList
      @_newExtendList = []
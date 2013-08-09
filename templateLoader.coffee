define [
  'cord-w'
  'dustjs-helpers'
  'cord!requirejs/pathConfig'
  'cord!utils/Future'
], (cord, dust, pathConfig, Future) ->

  loadWidgetTemplate: (path) ->
    ###
    Loads widget's template source into dust. Returns a Future which is completed when template is loaded.
    @return Future()
    ###
    if dust.cache[path]?
      Future.resolved()
    else
      info = cord.getFullInfo(path)
      Future.require("text!#{ pathConfig.bundles }/#{ info.relativeDirPath }/#{ info.dirName }.html.js")
        .andThen (err, tmplString) ->
          throw err if err
          dust.loadSource tmplString, path


  loadTemplate: (path, callback) ->
    require ["cord-t!" + path], ->
      callback()


  loadToDust: (path) ->
    ###
    Loads compiled dust template from the given path into the dust cache.
    Path is considered as relative to 'bundles' root, but must begin with slash (/).
    @return Future()
    ###
    if dust.cache[path]?
      Future.resolved()
    else
      Future.require("text!#{ pathConfig.bundles }#{ path }").map (tmplString) ->
        dust.register(path, dust.loadSource(tmplString))

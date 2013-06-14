define [
  'cord!Collection'
  'cord!Model'
  'cord!Module'
  'cord!isBrowser'
  'cord!utils/Defer'
  'cord!utils/Future'
  'underscore'
  'monologue' + (if document? then '' else '.js')
], (Collection, Model, Module, isBrowser, Defer, Future, _, Monologue) ->

  class ModelRepo extends Module
    @include Monologue.prototype

    model: Model

    _collections: null

    restResource: ''

    predefinedCollections: null

    fieldTags: null

    # key-value of available additional REST-API action names to inject into model instances as methods
    # key - action name
    # value - HTTP-method name in lower-case (get, post, put, delete)
    # @var Object[String -> String]
    actions: null


    constructor: (@container) ->
      throw new Error("'model' property should be set for the repository!") if not @model?
      @_collections = {}
      @_initPredefinedCollections()


    _initPredefinedCollections: ->
      ###
      Initiates hard-coded collections with their names and options based on the predefinedCollections proprerty.
      ###
      if @predefinedCollections?
        for name, options of @predefinedCollections
          collection = new Collection(this, name, options)
          @_registerCollection(name, collection)


    createCollection: (options) ->
      ###
      Just creates, registers and returns a new collection instance of existing collection if there is already
       a registered collection with the same options.
      @param Object options
      @return Collection
      ###
      name = Collection.generateName(options)
      if @_collections[name]?
        collection = @_collections[name]
      else
        collection = new Collection(this, name, options)
        @_registerCollection(name, collection)
      collection


    buildCollection: (options, syncMode, callback) ->
      ###
      Creates, syncs and returns in callback a new collection of this model type by the given options.
       If collection with the same options is already registered than this collection is returned
       instead of creating the new one.

      @see Collection::constructor()

      @param Object options should contain options accepted by collection constructor
      @param (optional)String syncMode desired sync and return mode, defaults to :sync
      @param Function(Collection) callback
      @return Collection
      ###

      if _.isFunction(syncMode)
        callback = syncMode
        syncMode = ':sync'

      collection = @createCollection(options)
      collection.sync(syncMode, callback)
      collection


    createSingleModel: (id, fields, extraOptions = {}) ->
      ###
      Creates and syncs single-model collection by id and field list. In callback returns resulting model.
       Method returns single-model collection.

      @param Integer id
      @param Array[String] fields list of fields names for the collection
      @return Collection|null
      ###
      
      options =
        id: id
        fields: fields
        reconnect: true

      options = _.extend extraOptions, options

      @createCollection(options)


    buildSingleModel: (id, fields, syncMode, callback) ->
      ###
      Creates and syncs single-model collection by id and field list. In callback returns resulting model.
       Method returns single-model collection.

      :now sync mode is not available here since we need to return the resulting model.

      @param Integer id
      @param Array[String] fields list of fields names for the collection
      @param (optional)String syncMode desired sync and return mode, default to :cache
             special sync mode :cache-async, tries to find model in existing collections,
             if not found, calls sync in async mode to refresh model
      @param Function(Model) callback
      @return Collection|null
      ###
      if syncMode == ':cache' || syncMode == ':cache-async'
        model = @probeCollectionsForModel(id, fields)
        if model
          console.log 'debug: buildSingleModel found in an existing collection'
          options =
             fields: fields
             id: model.id
             
          options.model = _.clone model
          collection = @createCollection(options)
          callback(collection.get(id))
          return collection
        else
          console.log 'debug: buildSingleModel missed in existing collections :('

      syncMode = ':async' if syncMode == ':cache-async'
      collection = @createSingleModel(id, fields)

      collection.sync syncMode, ->
        callback(collection.get(id))
      collection


    probeCollectionsForModel: (id, fields) ->
      ###
      Searches existing collections for needed model
      @param Integer id - id of needed model
      @param Array[String] fields list of fields names for a model
      @return Object|null - model or null if not found
      ###
      options=
        id: id
        fields: fields
      probeName = Collection.generateName(options, true)

      matchedCollections = _.filter @_collections, (collection, key) ->
        key.substr(0, probeName.length) == probeName

      for collection in matchedCollections
        if collection.have(id)
          return collection.get(id)

      null


    getCollection: (name, returnMode, callback) ->
      ###
      Returns registered collection by name. Returns collection immediately anyway regardless of
       that given in returnMode and callback. If returnMode is given than callback is required and called
       according to the returnMode value. If only callback is given, default returnMode is :now.

      @param String name collection's unique (in the scope of the repository) registered name
      @param (optional)String returnMode defines - when callback should be called
      @param (optional)Function(Collection) callback function with the resulting collection as an argument
                                                     to be called when returnMode decides
      ###
      if @_collections[name]?
        if _.isFunction(returnMode)
          callback = returnMode
          returnMode = ':now'
        else
          returnMode or= ':now'

        collection = @_collections[name]

        if returnMode == ':now'
          callback?(collection)
        else if callback?
          collection.sync(returnMode, callback)
        else
          throw new Error("Callback can be omitted only in case of :now return mode!")

        collection
      else
        throw new Error("There is no registered collection with name '#{ name }'!")


    _registerCollection: (name, collection) ->
      ###
      Validates and registers the given collection
      ###
      if @_collections[name]?
        throw new Error("Collection with name '#{ name }' is already registered in #{ @constructor.name }!")
      if not (collection instanceof Collection)
        throw new Error("Collection should be inherited from the base Collection class!")

      @_collections[name] = collection


    _fieldHasTag: (fieldName, tag) ->
      @fieldTags[fieldName]? and _.isArray(@fieldTags[fieldName]) and @fieldTags[fieldName].indexOf(tag) != -1


    # serialization related:

    toJSON: ->
      @_collections


    setCollections: (collections) ->
      @_collections = {}
      for name, info of collections
        collection = Collection.fromJSON(this, name, info)
        @_registerCollection(name, collection)


    # REST related

    query: (params, callback) ->
      resultPromise = Future.single()
      if @container
        @container.eval 'api', (api) =>
          apiParams = {}
          if params.reconnect == true
            apiParams.reconnect = true
          api.get @_buildApiRequestUrl(params), apiParams, (response, error) =>
            result = []
            if _.isArray(response)
              result.push(@buildModel(item)) for item in response
            else if response
              result.push(@buildModel(response))
            callback?(result)
            resultPromise.resolve(result)
      else
        resultPromise.reject('Cleaned up')

      resultPromise


    _buildApiRequestUrl: (params) ->
      urlParams = []
      if not params.id?
        urlParams.push("_filter=#{ params.filterId }") if params.filterId?
        urlParams.push("_sortby=#{ params.orderBy }") if params.orderBy?
        urlParams.push("_page=#{ params.page }") if params.page?
        urlParams.push("_pagesize=#{ params.pageSize }") if params.pageSize?
        # important! adding 1 to the params.end to compensate semantics:
        #   in the backend 'end' is meant as in javascript's Array.slice() - "not including"
        #   but in collection end is meant as the last index - "including"
        urlParams.push("_slice=#{ params.start },#{ params.end + 1 }") if params.start? or params.end?
        if params.filter
          for filterField of params.filter
            urlParams.push("#{ filterField }=#{ params.filter[filterField] }")

      if params.requestParams
        for requestParam of params.requestParams
          urlParams.push("#{ requestParam }=#{ params.requestParams[requestParam] }")

      commonFields = []
      calcFields = []
      for field in params.fields
        if @_fieldHasTag(field, ':backendCalc')
          calcFields.push(field)
        else
          commonFields.push(field)
      if commonFields.length > 0
        urlParams.push("_fields=#{ commonFields.join(',') }")
      else
        urlParams.push("_fields=id")
      urlParams.push("_calc=#{ calcFields.join(',') }") if calcFields.length > 0

      @restResource + (if params.id? then ('/' + params.id) else '') + '/?' + urlParams.join('&')


    save: (model) ->
      ###
      Persists list of given models to the backend
      @param Model model model to save
      @return Future(response, error)
      ###
      promise = new Future(1)
      if @container
        @container.eval 'api', (api) =>
          if model.id
            changeInfo = model.getChangedFields()
            changeInfo.id = model.id
            @emit 'change', changeInfo
            api.put @restResource + '/' + model.id, model.getChangedFields(), (response, error) =>
              if error
                @emit 'error', error
                promise.reject(error)
              else
                @cacheCollection(model.collection) if model.collection?
                model.resetChangedFields()
                @emit 'sync', model
                promise.resolve(response)
          else
            api.post @restResource, model.getChangedFields(), (response, error) =>
              if error
                @emit 'error', error
                promise.reject(error)
              else
                model.id = response.id
                model.resetChangedFields()
                @emit 'sync', model
                @_suggestNewModelToCollections(model)
                @_injectActionMethods(model)
                promise.resolve(response)
      else
        promise.reject('Cleaned up')
      promise


    paging: (params) ->
      ###
      Requests paging information from the backend.
      @param Object params paging and collection params
      @return Future(Object)
                total: Int (total count this collection's models)
                pages: Int (total number of pages)
                selected: Int (0-based index/position of the selected model)
                selectedPage: Int (1-based number of the page that contains the selected model)
      ###
      result = Future.single()
      if @container
        @container.eval 'api', (api) =>
          apiParams = {}
          apiParams._pagesize = params.pageSize if params.pageSize?
          apiParams._sortby = params.orderBy if params.orderBy?
          apiParams._selectedId = params.selectedId if params.selectedId?
          apiParams._filter = params.filterId if params.filterId?
          if params.filter
            for filterField of params.filter
              apiParams[filterField]=params.filter[filterField]

          api.get @restResource + '/paging/', apiParams, (response) =>
            result.resolve(response)
      else
        result.reject('Cleaned up')
      result


    emitModelChange: (model) ->
      if model instanceof Model
        changeInfo = model.toJSON()
        changeInfo.id = model.id
      else
        changeInfo = model
      @emit 'change', changeInfo


    callModelAction: (id, method, action, params) ->
      ###
      Request REST API action method for the given model
      @param Scalar id the model id
      @param String action the API action name on the model
      @param Object params additional key-value params for the action request (will be sent by POST)
      @return Future(response|error)
      ###
      result = new Future(1)
      if @container
        @container.eval 'api', (api) =>
          api[method] "#{ @restResource }/#{ id }/#{ action }", params, (response, error) ->
            if error
              result.reject(error)
            else
              result.resolve(response)
      else
        result.reject('Cleaned up')
      result


    buildModel: (attrs) ->
      ###
      Model factory.
      @param Object attrs key-value fields for the model, including the id (if exists)
      @return Model
      ###
      result = new @model(attrs)
      @_injectActionMethods(result) if attrs?.id
      result


    _suggestNewModelToCollections: (model) ->
      ###
      Notifies all available collections to check if they need to refresh with the new model
      ###
      Defer.nextTick =>
        for name, collection of @_collections
          collection.checkNewModel(model)


    _injectActionMethods: (model) ->
      ###
      Dynamically injects syntax-sugar-methods to call REST-API actions on the model instance as method-call
       with the name of the action. List of available action names must be set in the @action property of the
       model repository.
      @param Model model model which is injected with the methods
      @return Model the incoming model with injected methods
      ###
      if @actions?
        self = this
        for actionName, method of @actions
          do (actionName, method) ->
            model[actionName] = (params) ->
              self.callModelAction(@id, method, actionName, params)
      model


    # local caching related

    getTtl: ->
      600


    cacheCollection: (collection) ->
      name = collection.name
      result = new Future(1)
      if isBrowser
        require ['cord!cache/localStorage'], (storage) =>
          f = storage.saveCollectionInfo @constructor.name, name, collection.getTtl(),
            totalCount: collection._totalCount
            start: collection._loadedStart
            end: collection._loadedEnd
            hasLimits: collection._hasLimits
          result.when(f)

          result.when storage.saveCollection(@constructor.name, name, collection.toArray())

          result.resolve()

          result.fail (error) ->
            console.error "cacheCollection failed: ", error
      else
        result.reject("ModelRepo::cacheCollection is not applicable on server-side!")

      result


    cutCachedCollection: (collection, loadedStart, loadedEnd) ->
      if isBrowser
        result = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          f = storage.saveCollectionInfo @constructor.name, collection.name, null,
            totalCount: collection._totalCount
            start: loadedStart
            end: loadedEnd
          result.when(f)
      else
        Future.rejected("ModelRepo::cutCachedCollection is not applicable on server-side!")


    getCachedCollectionInfo: (name) ->
      if isBrowser
        result = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          result.when storage.getCollectionInfo(@constructor.name, name)
        result
      else
        Future.rejected("ModelRepo::getCachedCollectionInfo is not applicable on server-side!")


    getCachedCollectionModels: (name, fields) ->
      if isBrowser
        resultPromise = Future.single()
        require ['cord!cache/localStorage'], (storage) =>
          storage.getCollection(@constructor.name, name).done (models) =>
            result = []
            for m in models
              result.push(@buildModel(m))
            resultPromise.resolve(result)
        resultPromise
      else
        Future.rejected("ModelRepo::getCachedCollectionModels is not applicable on server-side!")


    _pathToObject: (pathList) ->
      result = {}
      for path in pathList
        changePointer = result
        parts = path.split('.')
        lastPart = parts.pop()
        # building structure based on dot-separated path
        for part in parts
          changePointer[part] = {}
          changePointer = changePointer[part]
        changePointer[lastPart] = true
      result


    _deepPick: (sourceObject, pattern) ->
      result = {}
      @_recursivePick(sourceObject, pattern, result)


    _recursivePick: (src, pattern, dst) ->
      for key, value of pattern
        if src[key] != undefined
          if value == true             # leaf of this branch
            dst[key] = src[key]
          else if _.isObject(src[key]) # value is object, diving deeper
            dst[key] = {}
            if @_recursivePick(src[key], value, dst[key]) == false
              return false
          else
            return false
        else
          return false
      dst


    _deepExtend: (args...) ->
      dst = args.shift()
      for src in args
        @_recursiveExtend(dst, src)
      dst


    _recursiveExtend: (dst, src) ->
      for key, value of src
        if value != undefined
          if dst[key] == undefined or _.isArray(value) or not _.isObject(dst[key])
            dst[key] = value
          else if _.isArray(value) or not _.isObject(value)
            dst[key] = value
          else
            @_recursiveExtend(dst[key], src[key])
      dst


    debug: (method) ->
      ###
      Return identification string of the current repository for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @constructor.name }#{ methodStr }"

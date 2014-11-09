define [
#  './handleThunk'
  './Vpatch'
  './vtree'
  'underscore'
], (Vpatch, vtree, _) ->

  diff = (a, b) ->
    patch = a: a
    walk a, b, patch, 0
    patch


  walk = (a, b, patch, index) ->
    if a == b
#      if vtree.isThunk(a) or vtree.isThunk(b)
#        thunks a, b, patch, index
#      else
      hooks b, patch, index
      return

    apply = patch[index]

    if not b?
      apply = appendPatch(apply, new VPatch(VPatch.REMOVE, a, b))
      destroyWidgets a, patch, index
#    else if vtree.isThunk(a) or vtree.isThunk(b)
#      thunks a, b, patch, index
    else if vtree.isVNode(b)
      if vtree.isVNode(a)
        if a.tagName == b.tagName and a.namespace == b.namespace and a.key == b.key
          propsPatch = diffProps(a.properties, b.properties, b.hooks)
          apply = appendPatch(apply, new VPatch(VPatch.PROPS, a, propsPatch))  if propsPatch
          apply = diffChildren(a, b, patch, apply, index)
        else
          apply = appendPatch(apply, new VPatch(VPatch.VNODE, a, b))
          destroyWidgets a, patch, index
      else
        apply = appendPatch(apply, new VPatch(VPatch.VNODE, a, b))
        destroyWidgets a, patch, index
    else if vtree.isVText(b)
      if not vtree.isVText(a)
        apply = appendPatch(apply, new VPatch(VPatch.VTEXT, a, b))
        destroyWidgets a, patch, index
      else if a.text != b.text
        apply = appendPatch(apply, new VPatch(VPatch.VTEXT, a, b))
    else if vtree.isWidget(b)
      apply = appendPatch(apply, new VPatch(VPatch.WIDGET, a, b))
      destroyWidgets(a, patch, index)  if not vtree.isWidget(a)

    patch[index] = apply  if apply
    return


  diffProps = (a, b, hooks) ->
    diff = undefined
    for aKey, aValue of a
      if not aKey of b
        diff or= {}
        diff[aKey] = undefined

      bValue = b[aKey]
      if hooks and (aKey of hooks)
        diff or= {}
        diff[aKey] = bValue
      else
        if _.isObject(aValue) and _.isObject(bValue)
          if getPrototype(bValue) != getPrototype(aValue)
            diff or= {}
            diff[aKey] = bValue
          else
            objectDiff = diffProps(aValue, bValue)
            if objectDiff
              diff or= {}
              diff[aKey] = objectDiff
        else if aValue != bValue
          diff or= {}
          diff[aKey] = bValue

    for bKey of b
      if not (bKey of a)
        diff or= {}
        diff[bKey] = b[bKey]

    diff


  getPrototype = (value) ->
    if Object.getPrototypeOf
      Object.getPrototypeOf value
    else if value.__proto__
      value.__proto__
    else if value.constructor
      value.constructor::


  diffChildren = (a, b, patch, apply, index) ->
    aChildren = a.children
    bChildren = reorder(aChildren, b.children)
    aLen = aChildren.length
    bLen = bChildren.length
    len = (if aLen > bLen then aLen else bLen)
    i = 0

    while i < len
      leftNode = aChildren[i]
      rightNode = bChildren[i]
      index += 1
      if not leftNode
        # Excess nodes in b need to be added
        apply = appendPatch(apply, new VPatch(VPatch.INSERT, null, rightNode))  if rightNode
      else if not rightNode
        if leftNode
          # Excess nodes in a need to be removed
          patch[index] = new VPatch(VPatch.REMOVE, leftNode, null)
          destroyWidgets leftNode, patch, index
      else
        walk leftNode, rightNode, patch, index

      index += leftNode.count  if vtree.isVNode(leftNode) and leftNode.count

      i++

    # Reorder nodes last
    apply = appendPatch(apply, new VPatch(VPatch.ORDER, a, bChildren.moves))  if bChildren.moves
    apply


  # Patch records for all destroyed widgets must be added because we need
  # a DOM node reference for the destroy function
  destroyWidgets = (vNode, patch, index) ->
    if vtree.isWidget(vNode)
      patch[index] = new VPatch(VPatch.REMOVE, vNode, null)  if typeof vNode.destroy == 'function'
    else if vtree.isVNode(vNode) and vNode.hasWidgets
      for child in vNode.children
        index += 1
        destroyWidgets child, patch, index
        index += child.count  if vtree.isVNode(child) and child.count
    return


#  # Create a sub-patch for thunks
#  thunks = (a, b, patch, index) ->
#    nodes = handleThunk(a, b)
#    thunkPatch = diff(nodes.a, nodes.b)
#    patch[index] = new VPatch(VPatch.THUNK, null, thunkPatch)  if hasPatches(thunkPatch)
#    return


  hasPatches = (patch) ->
    for index of patch
      return true  if index != 'a'
    false


  # Execute hooks when two nodes are identical
  hooks = (vNode, patch, index) ->
    if vtree.isVNode(vNode)
      patch[index] = new VPatch(VPatch.PROPS, vNode.hooks, vNode.hooks)  if vNode.hooks
      if vNode.descendantHooks
        for child in vNode.children
          index += 1
          hooks child, patch, index
          index += child.count  if vtree.isVNode(child) and child.count
    return


  # List diff, naive left to right reordering
  reorder = (aChildren, bChildren) ->
    bKeys = keyIndex(bChildren)
    return bChildren  if not bKeys

    aKeys = keyIndex(aChildren)
    return bChildren  if not aKeys

    bMatch = {}
    bMatch[bKeys[key]] = aKeys[key] for key of bKeys

    aMatch = {}
    aMatch[aKeys[key]] = bKeys[key] for key of aKeys

    aLen = aChildren.length
    bLen = bChildren.length
    len = (if aLen > bLen then aLen else bLen)

    shuffle = []
    freeIndex = 0
    i = 0
    moveIndex = 0
    moves = {}
    removes = moves.removes = {}
    reverse = moves.reverse = {}
    hasMoves = false

    while freeIndex < len
      move = aMatch[i]
      if move != undefined
        shuffle[i] = bChildren[move]
        if move != moveIndex
          moves[move] = moveIndex
          reverse[moveIndex] = move
          hasMoves = true
        moveIndex++
      else if i of aMatch
        shuffle[i] = undefined
        removes[i] = moveIndex++
        hasMoves = true
      else
        freeIndex++  while bMatch[freeIndex] != undefined
        if freeIndex < len
          freeChild = bChildren[freeIndex]
          if freeChild
            shuffle[i] = freeChild
            if freeIndex != moveIndex
              hasMoves = true
              moves[freeIndex] = moveIndex
              reverse[moveIndex] = freeIndex
            moveIndex++
          freeIndex++
      i++

    shuffle.moves = moves  if hasMoves

    shuffle


  keyIndex = (children) ->
    keys = undefined
    for child, i in children
      if child.key != undefined
        keys or= {}
        keys[child.key] = i
    keys


  appendPatch = (apply, patch) ->
    if apply
      if _.isArray(apply)
        apply.push patch
      else
        apply = [apply, patch]
      apply
    else
      patch



  diff
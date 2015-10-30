minimatch = require 'minimatch'

#--- localStorage DB
DB = (key) ->
  @key = key
  return @
DB.prototype.getData = ->
  data = localStorage[@key]
  data = if data? then JSON.parse(data) else {}
  return data
DB.prototype.setData = (data) ->
  localStorage[@key] = JSON.stringify(data)
DB.prototype.get = (name) ->
  data = @getData()
  return data[name]
DB.prototype.set = (name, value) ->
  data = @getData()
  data[name] = value
  @setData(data)


#--- OpenRecent
OpenRecent = ->
  @db = new DB('openRecent')
  @commandListenerDisposables = []
  return @

#--- OpenRecent: Event Handlers
OpenRecent.prototype.onLocalStorageEvent = (e) ->
  if e.key is @db.key
    @update()

OpenRecent.prototype.onUriOpened = ->
  editor = atom.workspace.getActiveTextEditor()
  filePath = editor?.buffer?.file?.path

  # Ignore anything thats not a file.
  return unless filePath
  return unless filePath.indexOf '://' is -1

  @insertFilePath(filePath) if filePath

OpenRecent.prototype.onProjectPathChange = (projectPaths) ->
  @insertCurrentPaths()


#--- OpenRecent: Listeners
OpenRecent.prototype.addCommandListeners = ->
  #--- Commands
  # open-recent:open-recent-file-#
  for index, path of @db.get('files')
    do (path) => # Explicit closure
      disposable = atom.commands.add "atom-workspace", "open-recent:open-recent-file-#{index}", =>
        @openFile path
      @commandListenerDisposables.push disposable

  # open-recent:open-recent-path-#
  for index, path of @db.get('paths')
    do (path) => # Explicit closure
      disposable = atom.commands.add "atom-workspace", "open-recent:open-recent-path-#{index}", =>
        @openPath path
      @commandListenerDisposables.push disposable

  # open-recent:clear
  disposable = atom.commands.add "atom-workspace", "open-recent:clear", =>
    @db.set('files', [])
    @db.set('paths', [])
    @update()
  @commandListenerDisposables.push disposable

OpenRecent.prototype.getProjectPath = (path) ->
  return atom.project.getPaths()?[0]

OpenRecent.prototype.openFile = (path) ->
  atom.workspace.open path

OpenRecent.prototype.openPath = (path) ->
  replaceCurrentProject = false
  options = {}

  if not @getProjectPath() and atom.config.get('open-recent.replaceNewWindowOnOpenDirectory')
    replaceCurrentProject = true
  else if @getProjectPath() and atom.config.get('open-recent.replaceProjectOnOpenDirectory')
    replaceCurrentProject = true

  if replaceCurrentProject
    atom.project.setPaths([path])
    if workspaceElement = atom.views.getView(atom.workspace)
      atom.commands.dispatch workspaceElement, 'tree-view:toggle-focus'
  else
    atom.open {
      pathsToOpen: [path]
      newWindow: !atom.config.get('open-recent.replaceNewWindowOnOpenDirectory')
    }

OpenRecent.prototype.addListeners = ->
  #--- Commands
  @addCommandListeners()

  #--- Events
  @onUriOpenedDisposable = atom.workspace.onDidOpen @onUriOpened.bind(@)
  @onDidChangePathsDisposable = atom.project.onDidChangePaths @onProjectPathChange.bind(@)

  # Notify other windows during a setting data in localStorage.
  window.addEventListener "storage", @onLocalStorageEvent.bind(@)

OpenRecent.prototype.removeCommandListeners = ->
  #--- Commands
  for disposable in @commandListenerDisposables
    disposable.dispose()
  @commandListenerDisposables = []

OpenRecent.prototype.removeListeners = ->
  #--- Commands
  @removeCommandListeners()

  #--- Events
  if @onUriOpenedDisposable
    @onUriOpenedDisposable.dispose()
    @onUriOpenedDisposable = null
  if @onDidChangePathsDisposable
    @onDidChangePathsDisposable.dispose()
    @onDidChangePathsDisposable = null
  window.removeEventListener 'storage', @onLocalStorageEvent.bind(@)

#--- OpenRecent: Methods
OpenRecent.prototype.init = ->
  @addListeners()

  # Defaults
  @db.set('paths', []) unless @db.get('paths')
  @db.set('files', []) unless @db.get('files')

  @insertCurrentPaths()
  @update()

# returns a Boolean if the path should be filtered, based on settings
OpenRecent.prototype.filterPath = (path) ->
  if atom.config.get('open-recent.ignoredNames') && ignoredNames = atom.config.get('core.ignoredNames')
    for name in ignoredNames
      match = [name, "**/#{name}/**"].some (comparison) ->
        minimatch(path, comparison, { matchBase: true, dot: true })
      return true if match

  false # default return value

OpenRecent.prototype.insertCurrentPaths = ->
  return unless atom.project.getDirectories().length > 0

  recentPaths = @db.get('paths')
  for projectDirectory, index in atom.project.getDirectories()
    # Ignore the second, third, ... folders in a project
    continue if index > 0 and not atom.config.get('open-recent.listDirectoriesAddedToProject')

    path = projectDirectory.path

    continue if @filterPath(path)

    # Remove if already listed
    index = recentPaths.indexOf path
    if index != -1
      recentPaths.splice index, 1

    recentPaths.splice 0, 0, path

    # Limit
    maxRecentDirectories = atom.config.get('open-recent.maxRecentDirectories')
    if recentPaths.length > maxRecentDirectories
      recentPaths.splice maxRecentDirectories, recentPaths.length - maxRecentDirectories

  @db.set('paths', recentPaths)
  @update()

 OpenRecent.prototype.insertFilePath = (path) ->
  return if @filterPath(path)

  recentFiles = @db.get('files')

  # Remove if already listed
  index = recentFiles.indexOf path
  if index != -1
    recentFiles.splice index, 1

  recentFiles.splice 0, 0, path

  # Limit
  maxRecentFiles = atom.config.get('open-recent.maxRecentFiles')
  if recentFiles.length > maxRecentFiles
    recentFiles.splice maxRecentFiles, recentFiles.length - maxRecentFiles

  @db.set('files', recentFiles)
  @update()

#--- OpenRecent: Menu
OpenRecent.prototype.createSubmenu = ->
  submenu = []
  submenu.push { command: "pane:reopen-closed-item", label: "Reopen Closed File" }
  submenu.push { type: "separator" }

  # Files
  recentFiles = @db.get('files')
  if recentFiles.length
    for index, path of recentFiles
      menuItem = {
        label: path
        command: "open-recent:open-recent-file-#{index}"
      }
      if path.length > 100
        menuItem.label = path.substr(-60)
        menuItem.sublabel = path
      submenu.push menuItem
    submenu.push { type: "separator" }

  # Root Paths
  recentPaths = @db.get('paths')
  if recentPaths.length
    for index, path of recentPaths
      menuItem = {
        label: path
        command: "open-recent:open-recent-path-#{index}"
      }
      if path.length > 100
        menuItem.label = path.substr(-60)
        menuItem.sublabel = path
      submenu.push menuItem
    submenu.push { type: "separator" }

  submenu.push { command: "open-recent:clear", label: "Clear List" }
  return submenu

OpenRecent.prototype.updateMenu = ->
  # Need to place our menu in top section
  for dropdown in atom.menu.template
    if dropdown.label is "File" or dropdown.label is "&File"
      for item in dropdown.submenu
        if item.command is "pane:reopen-closed-item" or item.label is "Open Recent"
          delete item.accelerator
          delete item.command
          delete item.click
          item.label = "Open Recent"
          item.enabled = true
          item.metadata ?= {}
          item.metadata.windowSpecific = false
          item.submenu = @createSubmenu()
          atom.menu.update()
          break # break for item
      break # break for dropdown

#--- OpenRecent:
OpenRecent.prototype.update = ->
  @removeCommandListeners()
  @updateMenu()
  @addCommandListeners()

OpenRecent.prototype.destroy = ->
  @removeListeners()


#--- Module
module.exports =
  config:
    maxRecentFiles:
      type: 'number'
      default: 8
    maxRecentDirectories:
      type: 'number'
      default: 8
    replaceNewWindowOnOpenDirectory:
      type: 'boolean'
      default: true
      description: 'When checked, opening a recent directory will "open" in the current window, but only if the window does not have a project path set. Eg: The window that appears when doing File > New Window.'
    replaceProjectOnOpenDirectory:
      type: 'boolean'
      default: false
      description: 'When checked, opening a recent directory will "open" in the current window, replacing the current project.'
    listDirectoriesAddedToProject:
      type: 'boolean'
      default: false
      description: 'When checked, the all root directories in a project will be added to the history and not just the 1st root directory.'
    ignoredNames:
      type: 'boolean'
      default: true
      description: 'When checked, skips files and directories specified in Atom\'s "Ignored Names" setting.'
  model: null

  activate: ->
    @model = new OpenRecent()
    @model.init()

  deactivate: ->
    @model.destroy()
    @model = null

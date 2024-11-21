local Config = require("dap-project-configuration.config")
local launcher = require("dap-project-configuration.launcher")
local M = {}

local popup = require("plenary.popup")

local Selection_winid = nil

--- Returns the savename for a given directory
--- @param dir string: the path to get a savename for
--- @return string
local function getSaveName(dir)
  local fname = dir:gsub("[\\/:]+", "%%")
  return Config.options.dir .. fname
end

--- Loads the saved selection for the current from the configured dir
--- @param cwd string: the current cwd
--- @return string|nil
local function loadSelection(cwd)
  local savename = getSaveName(cwd)
  if vim.fn.filereadable(savename) ~= 0 then
    for l in io.lines(savename) do
      if l ~= nil then
        return l
      end
    end
  end

  return nil
end

--- Saves the current selection for the cwd in the configured dir
--- @param cwd string: the current cwd
--- @param selname string: the selections name
local function saveSelection(cwd, selname)
  local savename = getSaveName(cwd)
  local f = io.open(savename, "w")
  if f ~= nil then
    f:write(selname)
    f:flush()
    f:close()
  end
end

--- Returns the default prelaunch config
--- @param cwd string: the current cwd
--- @return table
local function defaultPrelaunchConfig(cwd)
  return {
    cwd = cwd,
    env = {},
    cmd = nil,
    args = {},
    output = {
      target = "buffer",
      reuse = true,
      close_on_success = false,
      stop_on_close = true,
      autoscroll = false,
    },
    wait = true,
  }
end

--- Loads the configured filename from the given directory
--- @param cwd string: directory to look in
--- @return table|nil
local function loadProjectConfiguration(cwd)
  local cfgname = cwd .. "/" .. Config.options.filename
  if vim.fn.filereadable(cfgname) == 0 then
    return nil
  end

  local lf = loadfile(cfgname)
  if type(lf) ~= "function" then
    print("invalid project configuration in " .. cfgname .. " (not a function returned)")
    return nil
  end

  local cfg = lf()

  local defprelaunch = defaultPrelaunchConfig(cwd)
  for selkey, _ in pairs(cfg) do
    if cfg[selkey].prelaunch ~= nil then
      for plkey, pltable in pairs(cfg[selkey].prelaunch) do
        cfg[selkey].prelaunch[plkey] = vim.tbl_deep_extend("keep", pltable, defprelaunch)
      end
    end
  end

  return cfg
end

--- Closes the selection popup previously opened with ProjectDapSelect
M.close_selection = function()
  if Selection_winid ~= nil then
    vim.api.nvim_win_close(Selection_winid, true)
  end
end

--- Shows a popup to choose the selection of the current cwds project config
--- sets M.current_selection
M.select_configuration = function()
  local cfg = loadProjectConfiguration(vim.fn.getcwd())
  if cfg ~= nil then
    local keys = {}
    for k, _ in pairs(cfg) do
      table.insert(keys, k)
    end

    table.sort(keys)

    local width = 50
    local height = 30
    local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }

    local cb = function(_, sel)
      M.current_selection = sel
      saveSelection(vim.fn.getcwd(), M.current_selection)
    end

    Selection_winid = popup.create(keys, {
      title = "Select configuration",
      highlight = "NvimDapProjectSelection",
      line = math.floor(((vim.o.lines - height) / 2) - 1),
      col = math.floor((vim.o.columns - width) / 2),
      minwidth = width,
      minheight = height,
      borderchars = borderchars,
      callback = cb,
    })

    local bufnr = vim.api.nvim_win_get_buf(Selection_winid)
    vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>ProjectDapCloseSelection<CR>", { silent =  false })
  else
    print("no project configuration found in cwd")
  end
end

--- Stateful iterator of a table given in order of keys
--- @param keys table: list of keys giving the order of the iterator
--- @param tbl table: the table to work on
--- @return any, any: the next key value pair 
local function statefulTableIPairs(keys, tbl)
   local f, s, var = ipairs(keys)

   return function()
      local i, v = f(s, var)
      var = i
      return v, tbl[v]
   end
end

--- Launches all prelaunch tasks of a selection
--- @param selection string: the selection name
--- @param lcfg table: the prelaunch config table
--- @param cbafter function: callback to call after all prelaunch tasks run
local function launchAll(selection, lcfg, cbafter)
  local keys = vim.tbl_keys(lcfg)
  table.sort(keys)

  local iter = statefulTableIPairs(keys, lcfg)

  local function callnext(retcode, signal)
    if retcode ~= 0 or signal ~= 0 then
      return
    end

    local key, _ = iter()
    if key ~= nil then
      if lcfg[key].wait == true then
        launcher.launch(selection, key, lcfg[key], callnext)
      else
        launcher.launch(selection, key, lcfg[key], nil)
        callnext(0, 0)
      end
    else
      if cbafter ~= nil then
        cbafter()
      end
    end
  end

  callnext(0, 0)
end

--- Runs the subconfig given by the key and the config table
--- @param selection string: the selection name
--- @param cfg table: the config table of the selection
local function applyRunConfig(selection, cfg)
  local call_dap = function()
    if cfg.dap == nil then
      return
    end

    local rundap = Config.options.dapcmd
    if type(rundap) == "string" then
      vim.cmd(rundap)
    elseif type(rundap) == "function" then
      rundap()
    else
      print("invalid rundap in selection " .. selection)
    end
  end

  local provlist = {}
  local dapcfg = cfg["dap"]

  if dapcfg ~= nil then
    for _, v in pairs(dapcfg) do
      table.insert(provlist, v)
    end
  end

  local dap = require("dap")
  dap.providers.configs["nvim-dap-project-configuration"] = function()
    return provlist
  end

  local prelaunch = cfg["prelaunch"]
  if prelaunch ~= nil then
    launchAll(selection, prelaunch, call_dap)
  else
    call_dap()
  end
end

--- Runs the current selection config
M.run_selected = function()
  if M.current_selection == nil then
    print("nothing selected, run :ProjectDapSelect first")
    return
  end

  local cfg = loadProjectConfiguration(vim.fn.getcwd())
  if cfg ~= nil then
    if not vim.tbl_contains(vim.tbl_keys(cfg), M.current_selection) then
      print("selection '" .. M.current_selection .. "' not found in project configuration")
      M.current_selection = nil
      return
    end

    applyRunConfig(M.current_selection, cfg[M.current_selection])
  else
    print("no project configuration found in cwd")
  end
end

--- Stops all started prelaunch tasks
M.stop_all_tasks = function()
  launcher.stop_all_tasks()
end

M.setup = function(opts)
  Config.setup(opts)

  local projcfg = loadProjectConfiguration(vim.fn.getcwd())
  if projcfg ~= nil and vim.tbl_count(projcfg) == 1 then
    M.current_selection = vim.tbl_keys(projcfg)[1]
  else
    M.current_selection = loadSelection(vim.fn.getcwd())
  end

  vim.api.nvim_create_user_command("ProjectDapSelect", M.select_configuration, {})
  vim.api.nvim_create_user_command("ProjectDapRun", M.run_selected, {})
  vim.api.nvim_create_user_command("ProjectDapCloseSelection", M.close_selection, {})
  vim.api.nvim_create_user_command("ProjectDapStopAllTasks", M.stop_all_tasks, {})

  vim.api.nvim_create_autocmd({"BufWipeout"}, {
    callback = launcher.on_buffer_closed
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = M.stop_all_tasks
  })
end

return M

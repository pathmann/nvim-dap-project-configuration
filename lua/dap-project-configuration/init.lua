local Config = require("dap-project-configuration.config")
local Utils = require("dap-project-configuration.utils")
local launcher = require("dap-project-configuration.launcher")
local popup = require("plenary.popup")

local M = {}
M.current_selection = nil
M.run_dap = true

local Selection_winid = nil


--- Returns the savename for a given directory
--- @param dir string: the path to get a savename for
--- @return string
local function getSaveName(dir)
  local fname = dir:gsub("[\\/:]+", "%%")
  return Config.options.dir .. fname
end

--- Load the state for the cwd from the configured dir
--- @param cwd string: the current cwd
local function loadState(cwd)
  M.current_selection = nil

  local savename = getSaveName(cwd)
  if vim.fn.filereadable(savename) ~= 0 then
    local file = io.open(savename, "r")
    if not file then
      return
    end

    local content = file:read("*a")
    file:close()

    local ok, json = pcall(vim.fn.json_decode, content)
    if not ok or not json then
      return
    end

    M.current_selection = json["current_selection"]
    M.run_dap = json["run_dap"]
  end
end

--- Saves the state for the cwd to the configured dir
--- @param cwd string: the current cwd
local function saveState(cwd)
  local savename = getSaveName(cwd)
  local file = io.open(savename, "w")
  if not file then
    print("nvim-dap-project-configuration: error writing statefile")
    return
  end

  local state = {}
  state["current_selection"] = M.current_selection
  state["run_dap"] = M.run_dap

  file:write(vim.fn.json_encode(state))
  file:close()
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
      clear = false,
      close_on_success = false,
      stop_on_close = true,
      autoscroll = false,
    },
    wait = true,
  }
end

--- Loads the configured filename from the given directory
--- @param cwd string: directory to look in
--- @return table|nil, table|nil
local function loadProjectConfiguration(cwd)
  local cfgname = cwd .. "/" .. Config.options.filename
  if vim.fn.filereadable(cfgname) == 0 then
    return nil, nil
  end

  local lf = loadfile(cfgname)
  if type(lf) ~= "function" then
    print("invalid project configuration in " .. cfgname .. " (not a function returned)")
    return nil, nil
  end

  local cfg, cbs = lf()

  local defprelaunch = defaultPrelaunchConfig(cwd)
  for selkey, _ in pairs(cfg) do
    if cfg[selkey].prelaunch ~= nil then
      for plkey, pltable in pairs(cfg[selkey].prelaunch) do
        cfg[selkey].prelaunch[plkey] = vim.tbl_deep_extend("keep", pltable, defprelaunch)
      end
    end
  end

  return cfg, cbs
end

--- Closes the selection popup previously opened with ProjectDapSelect
M.close_selection = function()
  if Selection_winid ~= nil then
    vim.api.nvim_win_close(Selection_winid, true)
    Selection_winid = nil
  end
end

--- Shows a popup to choose the selection of the current cwds project config
--- sets M.current_selection
M.select_configuration = function(args)
  local cfg, usercbs = loadProjectConfiguration(vim.fn.getcwd())
  if cfg ~= nil then
    local keys = {}
    for k, _ in pairs(cfg) do
      table.insert(keys, k)
    end

    if not vim.tbl_isempty(args.fargs) then
      if vim.tbl_contains(keys, args.fargs[1]) then
        M.current_selection = args.fargs[1]
        saveState(vim.fn.getcwd())

        if usercbs ~= nil and usercbs.on_select ~= nil then
          if type(usercbs.on_select) ~= "function" then
            print("callback on_select is not a function")
            return
          end

          usercbs.on_select(args.fargs[1])
      end
      else
        print("no such configuration found")
      end

      return
    end

    table.sort(keys)

    local width = 50
    local height = 30
    local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }

    local cb = function(_, sel)
      M.current_selection = sel
      saveState(vim.fn.getcwd())
      Selection_winid = nil

      if usercbs ~= nil and usercbs.on_select ~= nil then
        if type(usercbs.on_select) ~= "function" then
          print("callback on_select is not a function")
          return
        end

        usercbs.on_select(sel)
      end
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
      local wait = lcfg[key].wait
      if (type(wait) == "boolean" and wait == true) or (type(wait) == "number") then
        launcher.launch(selection, key, lcfg[key], callnext, Config.options.ignore_win_to_close)
      else
        launcher.launch(selection, key, lcfg[key], nil, Config.options.ignore_win_to_close)
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

--- Extracts all parameters from a dap configuration provider and returns it as launch table for launcher.launch
--- @param dapcfg table: the config provider
--- @returns: table
local function dapConfigToLaunchConfig(dapcfg)
  local ret = {}

  ret.cwd = dapcfg.cwd
  ret.cmd = dapcfg.program
  ret.args = dapcfg.args
  ret.env = dapcfg.env

  return ret
end

--- Runs the subconfig given by the key and the config table
--- @param selection string: the selection name
--- @param cfg table: the config table of the selection
--- @param rundap boolean: if true, run dapcmd, else execute launch config
local function applyRunConfig(selection, cfg, rundap)
  local call_after = function()
    if rundap then
      if cfg.dap == nil then
        return
      end

      local dapcmd = Config.options.dapcmd
      if type(dapcmd) == "string" then
        vim.cmd(dapcmd)
      elseif type(dapcmd) == "function" then
        dapcmd()
      else
        print("invalid rundap in selection " .. selection)
      end
    else --- launch app
      if cfg.run == nil then
        return
      end

      local runcfg = cfg.run.launch

      local cmdtable = defaultPrelaunchConfig(vim.fn.getcwd())
      cmdtable.wait = false

      if type(runcfg) == "string" then
        cmdtable = vim.tbl_deep_extend("force", cmdtable, dapConfigToLaunchConfig(cfg.dap[runcfg]))
      elseif type(runcfg) == "table" then
        cmdtable = vim.tbl_deep_extend("force", cmdtable, runcfg)
      else
        return
      end

      cmdtable.output = vim.tbl_deep_extend("force", cmdtable.output, cfg.run.output or {})

      launcher.launch(selection, "launch", cmdtable, nil, Config.options.ignore_win_to_close)
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
    launchAll(selection, prelaunch, call_after)
  else
    call_after()
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

    applyRunConfig(M.current_selection, cfg[M.current_selection], M.run_dap)
  else
    print("no project configuration found in cwd")
  end
end

--- Stops all started prelaunch tasks
M.stop_all_tasks = function()
  launcher.stop_all_tasks()
end

M.toggle_dap_run = function()
  M.run_dap = not M.run_dap
  saveState(vim.fn.getcwd())
end

M.enable_dap = function()
  M.run_dap = true
  saveState(vim.fn.getcwd())
end

M.disable_dap = function()
  M.run_dap = false
  saveState(vim.fn.getcwd())
end

M.select_dap = function()
  M.close_selection()

  local width = 50
  local height = 30
  local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }

  local cb = function(_, sel)
    M.run_dap = sel == "DAP"
    saveState(vim.fn.getcwd())
    Selection_winid = nil
  end

  Selection_winid = popup.create({"DAP", "Run"}, {
    title = "Select DAP or Run",
    highlight = "NvimDapProjectDAPSelection",
    line = math.floor(((vim.o.lines - height) / 2) - 1),
    col = math.floor((vim.o.columns - width) / 2),
    minwidth = width,
    minheight = height,
    borderchars = borderchars,
    callback = cb,
  })

  local bufnr = vim.api.nvim_win_get_buf(Selection_winid)
  vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>ProjectDapCloseSelection<CR>", { silent =  false })
end

local function listSelections()
  local cfg = loadProjectConfiguration(vim.fn.getcwd())
  if cfg == nil then
    return {}
  end

  return vim.tbl_keys(cfg)
end

local function filterPrefix(tbl, pref)
  local filtered = vim.tbl_filter(function(it)
    return vim.startswith(it, pref)
  end, tbl)
  return filtered
end

local function completeSelections(argprefix)
  local allsels = listSelections()
  return filterPrefix(allsels, argprefix)
end

local function empty_project()
  return [[
  return {
    build = {
      dap = nil,
      run = {
        launch = {
          cmd = "",
          args = {},
          cwd = vim.fn.getcwd(),
          env = vim.fn.environ(),
        },
        output = {
          target = "buffer",
          reuse = true,
          clear = true,
          close_on_success = true,
          stop_on_close = true,
          autoscroll = true,
        }
      },
    },
}, {
  on_select = function(target)

  end,
}
  ]]
end

local function open_tabbed_buffer(filename, content)
  vim.cmd("tabnew")

  local buf = vim.api.nvim_create_buf(true, false)

  local lines = vim.split(content, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  vim.api.nvim_buf_set_name(buf, filename)

  vim.api.nvim_set_current_buf(buf)

  vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
  vim.api.nvim_set_option_value("readonly", false, { buf = buf })
  vim.api.nvim_set_option_value("filetype", "lua", { buf = buf })

  vim.bo.modified = true
end

M.create_configuration = function(args)
  local confname = vim.fn.getcwd() .. "/" .. Config.options.filename

  if vim.fn.filereadable(confname) == 1 then
    print("project config already exists")
    return
  end

  local lang = args.fargs[1] or nil

  if lang == nil then
    local detfunc = Config.options.detect_language or Utils.detect_language
    lang = detfunc(vim.fn.getcwd(), vim.api.nvim_get_current_buf())
  end

  local tpl = empty_project()

  if lang == nil then
    print("language was not detected, creating empty project file")
  else
    local tplfunc = Config.options.config_templates[lang]

    if tplfunc == nil then
      print("no template found for lang " .. lang .. ", creating empty project file")
    else
      tpl = tplfunc(vim.fn.getcwd())
    end
  end

  open_tabbed_buffer(confname, tpl)
end

M.setup = function(opts)
  Config.setup(opts)

  loadState(vim.fn.getcwd())

  local projcfg, usercbs = loadProjectConfiguration(vim.fn.getcwd())
  if projcfg ~= nil and vim.tbl_count(projcfg) == 1 then
    M.current_selection = vim.tbl_keys(projcfg)[1]
  end

  if M.current_selection ~= nil and usercbs ~= nil and usercbs.on_select ~= nil then
    if type(usercbs.on_select) ~= "function" then
      print("callback on_select is not a function")
      return
    end

    usercbs.on_select(M.current_selection)
  end

  vim.api.nvim_create_user_command("ProjectDapSelect", M.select_configuration, { nargs="?", complete=completeSelections })
  vim.api.nvim_create_user_command("ProjectDapRun", M.run_selected, {})
  vim.api.nvim_create_user_command("ProjectDapCloseSelection", M.close_selection, {})
  vim.api.nvim_create_user_command("ProjectDapStopAllTasks", M.stop_all_tasks, {})
  vim.api.nvim_create_user_command("ProjectDapToggleDap", M.toggle_dap_run, {})
  vim.api.nvim_create_user_command("ProjectDapEnableDap", M.enable_dap, {})
  vim.api.nvim_create_user_command("ProjectDapDisableDap", M.disable_dap, {})
  vim.api.nvim_create_user_command("ProjectDapSelectDap", M.select_dap, {})
  vim.api.nvim_create_user_command("ProjectDapCreate", M.create_configuration, { nargs="?" })


  vim.api.nvim_create_autocmd({"BufWipeout"}, {
    callback = launcher.on_buffer_closed
  })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = M.stop_all_tasks
  })
end

return M

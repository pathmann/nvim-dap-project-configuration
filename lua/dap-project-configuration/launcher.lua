local M = {}

local job = require("plenary.job")

M.task_bufs_running = {}

local signalCache = {
  [1] = "SIGHUP",
  [2] = "SIGINT",
  [3] = "SIGQUIT",
  [4] = "SIGILL",
  [5] = "SIGTRAP",
  [6] = "SIGABRT",
  [7] = "SIGBUS",
  [8] = "SIGFPE",
  [9] = "SIGKILL",
  [10] = "SIGUSR1",
  [11] = "SIGSEGV",
  [12] = "SIGUSR2",
  [13] = "SIGPIPE",
  [14] = "SIGALRM",
  [15] = "SIGTERM",
  [16] = "SIGSTKFLT",
  [17] = "SIGCHLD",
  [18] = "SIGCONT",
  [19] = "SIGSTOP",
  [20] = "SIGTSTP",
  [21] = "SIGTTIN",
  [22] = "SIGTTOU",
  [23] = "SIGURG",
  [24] = "SIGXCPU",
  [25] = "SIGXFSZ",
  [26] = "SIGVTALRM",
  [27] = "SIGPROF",
  [28] = "SIGWINCH",
  [29] = "SIGIO",
}

local function signalName(signal)
  local ret = signalCache[signal]
  if ret then
    return ret
  end

  local _handle = io.popen("kill -l " .. signal)
  if _handle ~= nil then
    ret = _handle:read("*all")
    _handle:close()

    if ret ~= nil then
      signalCache[signal] = ret
      return ret
    end

    return signal
  end
end

local function killPid(pid)
  local _handle = io.popen("kill " .. pid)
  if _handle ~= nil then
    _handle:close()
    return true
  end

  return false
end

M.stop_all_tasks = function()
  for pid, buf in pairs(M.task_bufs_running) do
    if killPid(pid) then
      if buf ~= -1 then
        pcall(vim.api.nvim_buf_del_var, buf, "nvim-dap-project-configuration.pid")
      end
    end
  end

  M.task_bufs_running = {}
end

local function findBuffer(selection, cmdname)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ok, cmdvar = pcall(vim.api.nvim_buf_get_var, buf, 'nvim-dap-project-configuration')

    if ok and cmdvar == selection .. ":" .. cmdname then
      local windows = vim.fn.win_findbuf(buf)

      return buf, windows[1]
    end
  end

  return nil, 0
end

local function createBuffer(selection, cmdname, ft)
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_name(buf, selection .. ":" .. cmdname .. ":" .. os.date("%Y-%m-%d %H:%M:%S"))
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  vim.api.nvim_set_option_value("filetype", ft, { buf = buf })

  vim.api.nvim_buf_set_var(buf, "nvim-dap-project-configuration", selection .. ":" .. cmdname)

  vim.cmd("tabnew")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)

  return buf, win
end

M.launch = function(selection, cmdname, cmdtable, callafter, ignorewinfunc)
  local buf = nil
  local win = 0

  local function bufprint(error, data)
    if buf == nil then
      return
    end

    vim.schedule(function()
      local ok = pcall(vim.api.nvim_set_option_value, "modifiable", true, { buf = buf })

      --there might still be output leftover when closing the buffer
      if not ok then
        return
      end

      local lines = nil
      if error ~= nil then
        lines = vim.split(error, "\n")
      elseif data ~= nil then
        lines = vim.split(data, "\n")
      end

      if lines ~= nil then
        vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)

        if cmdtable.output.autoscroll then
          local last_line = vim.api.nvim_buf_line_count(buf)
          local last_line_content = vim.api.nvim_buf_get_lines(buf, last_line - 1, last_line, false)[1] or ""
          local last_column = #last_line_content
          vim.api.nvim_win_set_cursor(win, { last_line, last_column })
        end
      end

      vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    end)
  end

  if cmdtable.output.target == "buffer" and cmdtable.output.reuse then
    buf, win = findBuffer(selection, cmdname)

    if buf ~= nil then
      if cmdtable.output.clear then
        vim.schedule(function()
          vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
          vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
        end)
      end

      local ok, pid = pcall(vim.api.nvim_buf_get_var, buf, 'nvim-dap-project-configuration.pid')
      if ok and pid then
        vim.api.nvim_buf_del_var(buf, "nvim-dap-project-configuration.pid")
        killPid(pid)
        bufprint("*** nvim-dap-project-configuration: Process killed ***")
      end
    end
  end

  if cmdtable.output.target == "buffer" and buf == nil then
    buf, win = createBuffer(selection, cmdname, cmdtable.output.filetype)
  end

  local printfunc = nil
  if cmdtable.output.target == "buffer" then
    printfunc = bufprint
  elseif cmdtable.output.target == "print" then
    printfunc = function(error, data)
      if error then
        print(error)
      else
        print(data)
      end
    end
  elseif type(cmdtable.output.target == "function") then
    printfunc = cmdtable.output.target
  end

  local cmd = cmdtable.cmd
  if type(cmd) == "function" then
    cmd = cmd()
  end

  local j = job:new({
    command = cmd,
    args = cmdtable.args,
    cwd = cmdtable.cwd,
    env = cmdtable.env,
    on_stdout = printfunc,
    on_stderr = printfunc,
    on_exit = function(j, code, signal)
      M.task_bufs_running[j.pid] = nil

      if code == 0 and signal == 0 then
        if buf ~= nil then
          if cmdtable.output.close_on_success then
            vim.schedule(function()
              local ok, pid = pcall(vim.api.nvim_buf_get_var, buf, "nvim-dap-project-configuration.pid")
              if ok and pid == j.pid then
                vim.api.nvim_buf_del_var(buf, "nvim-dap-project-configuration.pid")

                local win_id = vim.fn.bufwinid(buf)

                if win_id ~= -1 then
                  -- there might be windows opened on this tab
                  -- if so, check if we can ignore them

                  local tab_id = vim.api.nvim_win_get_tabpage(win_id)
                  local all_wins = vim.api.nvim_tabpage_list_wins(tab_id)
                  for _, wid in ipairs(all_wins) do
                    if wid ~= win_id then
                      if ignorewinfunc == nil or not ignorewinfunc(wid) then
                        return
                      end
                    end
                  end

                  vim.api.nvim_set_current_tabpage(tab_id)
                  vim.cmd('tabclose')
                end
              end
            end)
          else
            bufprint(nil, "*** nvim-dap-project-configuration: Done ***")
          end
        end
      else
        if buf ~= nil then
          vim.schedule(function()
            local ok, pid = pcall(vim.api.nvim_buf_get_var, buf, "nvim-dap-project-configuration.pid")
            if ok and pid == j.pid then
              vim.api.nvim_buf_del_var(buf, "nvim-dap-project-configuration.pid")
            end
          end)
        end

        if printfunc then
          printfunc("*** nvim-dap-project-configuration: Process returned exit code " .. code .. " " .. signalName(signal) .. " ***", nil)
        end
      end

      if callafter ~= nil then
        vim.schedule(function()
          callafter(code, signal)
        end)
      end
    end,
  })

  j:start()

  M.task_bufs_running[j.pid] = buf or -1

  if buf ~= nil then
    vim.api.nvim_buf_set_var(buf, "nvim-dap-project-configuration.pid", j.pid)
  end
end

M.on_buffer_closed = function(args)
  local buf = args.buf
  local ok, pid = pcall(vim.api.nvim_buf_get_var, buf, 'nvim-dap-project-configuration.pid')

  if ok and pid then
    if killPid(pid) then
      vim.api.nvim_buf_del_var(buf, "nvim-dap-project-configuration.pid")
      M.task_bufs_running[pid] = nil
    end
  end
end

return M

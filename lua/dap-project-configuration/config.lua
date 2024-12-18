local M = {}

local defaults = {
  dir = vim.fn.stdpath("state") .. "/dap-project-configuration/",
  filename = ".nvim-dap-project-configuration.lua",
  dapcmd = "DapContinue",
  ignore_win_to_close = nil,
}

M.options = {}

M.setup = function(opts)
  M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  vim.fn.mkdir(M.options.dir, "p")
end

return M


local M = {}

local defaults = {
  dir = vim.fn.stdpath("state") .. "/dap-project-configuration/",
  filename = ".nvim-dap-project-configuration.lua",
  dapcmd = "DapContinue",
}

M.options = {}

M.setup = function(opts)
  M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})

  vim.fn.mkdir(M.options.dir, "p")
end

return M


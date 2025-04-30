local M = {}

--- Try to detect the current language/filetype in cwd 
function M.detect_language(rootdir, curbuf)
  if vim.fn.filereadable(rootdir .. "/Cargo.toml") == 1 then
    return "rust"
  end

  if vim.fn.filereadable(rootdir .. "/requirements.txt") == 1 then
    return "python"
  end

  return vim.bo[curbuf].filetype
end

return M

return {
  "AstroNvim/AstroNvim",
  init = function()
    vim.api.nvim_set_hl(0, "Normal", { bg = nil })
    vim.api.nvim_set_hl(0, "NormalFloat", { bg = nil })
    vim.api.nvim_set_hl(0, "SignColumn", { bg = nil })
    vim.api.nvim_set_hl(0, "LineNr", { bg = nil })
    vim.api.nvim_set_hl(0, "CursorLineNr", { bg = nil })
  end,
}

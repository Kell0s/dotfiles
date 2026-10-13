-- Убираем серые надписи внутри кода (имена параметров, типы, "run test" и т.п.).
-- Включить обратно на время: <leader>uh
return {
  "neovim/nvim-lspconfig",
  opts = {
    inlay_hints = { enabled = false },
    codelens = { enabled = false },
    diagnostics = { update_in_insert = false },
  },
}

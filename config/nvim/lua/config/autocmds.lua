-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")
-- >>> kellos-templates >>>
-- Заготовки для новых файлов .c / .h / .go
local AUTHOR = "Kellos"

local function put(lines, row, col)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  pcall(vim.api.nvim_win_set_cursor, 0, { row, col or 0 })
end

local function go_package(dir)
  for _, f in ipairs(vim.fn.glob(dir .. "/*.go", false, true)) do
    if f ~= vim.fn.expand("%:p") then
      for _, line in ipairs(vim.fn.readfile(f, "", 40)) do
        local pkg = line:match("^package%s+([%w_]+)")
        if pkg then return (pkg:gsub("_test$", "")) end
      end
    end
  end
  return "main"
end

vim.api.nvim_create_autocmd("BufNewFile", {
  group = vim.api.nvim_create_augroup("kellos_templates", { clear = true }),
  pattern = { "*.c", "*.h", "*.go" },
  callback = function(ev)
    local name = vim.fn.fnamemodify(ev.file, ":t")
    local date = os.date("%d.%m.%Y")
    local ext = vim.fn.fnamemodify(ev.file, ":e")

    if ext == "c" then
      put({
        "/*",
        " * " .. name,
        " * Автор: " .. AUTHOR .. ", " .. date,
        " */",
        "",
        "#include <stdio.h>",
        "#include <stdlib.h>",
        "",
        "int main(void) {",
        "    ",
        "    return 0;",
        "}",
      }, 10, 4)
    elseif ext == "h" then
      local guard = name:upper():gsub("[^%w]", "_")
      put({
        "/*",
        " * " .. name,
        " * Автор: " .. AUTHOR .. ", " .. date,
        " */",
        "",
        "#ifndef " .. guard,
        "#define " .. guard,
        "",
        "",
        "",
        "#endif /* " .. guard .. " */",
      }, 9, 0)
    elseif ext == "go" then
      local dir = vim.fn.fnamemodify(ev.file, ":p:h")
      local pkg = go_package(dir)
      local header = { "// " .. name .. " — " .. AUTHOR .. ", " .. date, "" }
      if name:match("_test%.go$") then
        put(vim.list_extend(header, {
          "package " .. pkg,
          "",
          'import "testing"',
          "",
          "func Test(t *testing.T) {",
          "\t",
          "}",
        }), 8, 1)
      elseif pkg == "main" then
        put(vim.list_extend(header, {
          "package main",
          "",
          'import "fmt"',
          "",
          "func main() {",
          '\tfmt.Println("")',
          "}",
        }), 8, 14)
      else
        put(vim.list_extend(header, { "package " .. pkg, "", "" }), 5, 0)
      end
    end
  end,
})
-- <<< kellos-templates <<<
-- >>> kellos-transparent >>>
local function kellos_transparent()
  for _, g in ipairs({
    "Normal", "NormalNC", "NormalFloat", "FloatBorder", "FloatTitle",
    "SignColumn", "EndOfBuffer", "LineNr", "CursorLineNr", "FoldColumn",
    "StatusLine", "StatusLineNC", "TabLine", "TabLineFill", "WinSeparator",
    "Pmenu", "SnacksPicker", "SnacksPickerBorder", "SnacksDashboardNormal",
    "NeoTreeNormal", "NeoTreeNormalNC", "BufferLineFill",
  }) do
    local hl = vim.api.nvim_get_hl(0, { name = g, link = false })
    hl.bg = nil
    hl.ctermbg = nil
    vim.api.nvim_set_hl(0, g, hl)
  end
end
vim.api.nvim_create_autocmd("ColorScheme", { callback = kellos_transparent })
kellos_transparent()
-- <<< kellos-transparent <<<
-- >>> kellos-hl >>>
-- Подсветка кода Kellos: одна фиолетово-розовая гамма, типы — тёплые
local function kellos_hl()
  local c = {
    kw = "#b48efa", fn = "#9db0ff", ty = "#f9e2af", str = "#f0b6d9",
    num = "#e9a6f2", text = "#e0d4f5", member = "#c9adff", module = "#f5a9e0",
    op = "#96aef0", punct = "#8c7aa8", comment = "#7d6b98",
  }
  local set = function(g, v) vim.api.nvim_set_hl(0, g, v) end
  local groups = {
    [c.kw]  = { "Keyword", "Statement", "Conditional", "Repeat", "Include", "@keyword", "@keyword.function",
                "@keyword.return", "@keyword.import", "@keyword.conditional", "@keyword.repeat", "@keyword.type" },
    [c.fn]  = { "Function", "@function", "@function.call", "@function.method", "@function.method.call",
                "@lsp.type.function", "@lsp.type.method" },
    [c.ty]  = { "Type", "@type", "@type.builtin", "@type.definition", "@lsp.type.type", "@lsp.type.struct",
                "@lsp.type.interface", "@lsp.type.typeParameter" },
    [c.str] = { "String", "@string", "@string.escape", "@lsp.type.string", "Character" },
    [c.num] = { "Number", "Float", "Boolean", "Constant", "@number", "@boolean", "@constant", "@constant.builtin" },
    [c.text]= { "@variable", "@lsp.type.variable", "Identifier" },
    [c.member] = { "@variable.member", "@property", "@field", "@lsp.type.property" },
    [c.module] = { "@module", "@namespace", "@lsp.type.namespace" },
    [c.op]  = { "Operator", "@operator" },
    [c.punct] = { "Delimiter", "@punctuation.bracket", "@punctuation.delimiter" },
  }
  for color, list in pairs(groups) do
    for _, g in ipairs(list) do set(g, { fg = color }) end
  end
  set("@variable.parameter", { fg = c.text, italic = true })
  set("@lsp.type.parameter", { fg = c.text, italic = true })
  set("Comment", { fg = c.comment, italic = true })
  set("@comment", { fg = c.comment, italic = true })
  set("CursorLineNr", { fg = c.kw, bold = true })
  set("LineNr", { fg = "#4a3a66" })
  set("CursorLine", { bg = "#21163a" })
  set("Visual", { bg = "#3b2d55" })
  set("DiagnosticWarn", { fg = "#e8c88a" })
  set("DiagnosticVirtualTextWarn", { fg = "#a8916a", italic = true })
  set("DiagnosticVirtualTextError", { fg = "#c9718c", italic = true })
  set("DiagnosticVirtualTextInfo", { fg = c.comment, italic = true })
  set("DiagnosticVirtualTextHint", { fg = c.comment, italic = true })
end
vim.api.nvim_create_autocmd("ColorScheme", { callback = kellos_hl })
kellos_hl()
-- <<< kellos-hl <<<
-- >>> kellos-header >>>
vim.api.nvim_create_autocmd("BufNewFile", {
  pattern = { "*.c", "*.h", "*.go", "*.py" },
  callback = function()
    local name = vim.fn.expand("%:t")
    local author = vim.trim(vim.fn.system("git config user.name"))
    if author == "" or author:find("fatal") then author = "Kellos" end
    local date = os.date("%Y-%m-%d %H:%M")
    local lines
    if name:match("%.py$") then
      lines = { "# file:    " .. name, "# author:  " .. author, "# created: " .. date, "" }
    elseif name:match("%.go$") then
      lines = { "// file:    " .. name, "// author:  " .. author, "// created: " .. date, "" }
    else
      lines = { "/*", " * file:    " .. name, " * author:  " .. author, " * created: " .. date, " */", "" }
    end
    vim.api.nvim_buf_set_lines(0, 0, 0, false, lines)
    vim.api.nvim_win_set_cursor(0, { #lines, 0 })
  end,
})
-- <<< kellos-header <<<

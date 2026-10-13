-- Kellos: Catppuccin Mocha, полностью перекрашенный в фиолетово-розовую гамму
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000,
    opts = {
      flavour = "mocha",
      transparent_background = true,
      float = { transparent = true },
      styles = { comments = { "italic" }, keywords = {}, conditionals = {} },
      color_overrides = {
        mocha = {
          -- фон и текст
          base = "#160e24", mantle = "#120b1d", crust = "#0d0816",
          surface0 = "#271a3d", surface1 = "#3b2d55", surface2 = "#4a3a66",
          overlay0 = "#6b5a85", overlay1 = "#7d6b98", overlay2 = "#8c7aa8",
          subtext0 = "#b3a5cc", subtext1 = "#c9bce0", text = "#e0d4f5",
          -- подсветка: всё в одной гамме
          mauve = "#b48efa",     -- ключевые слова (func, return, import)
          blue = "#9db0ff",      -- функции
          lavender = "#c9adff",  -- переменные/параметры
          yellow = "#d7c2ff",    -- типы (string, int)
          green = "#f0b6d9",     -- строки
          peach = "#e9a6f2",     -- числа и константы
          pink = "#f5a9e0",
          flamingo = "#eebfe6", rosewater = "#f2d5ee", maroon = "#e79ac0",
          teal = "#a9bdf5", sky = "#b6c4f2", sapphire = "#96aef0",
          red = "#f38ba8",       -- только ошибки
        },
      },
      custom_highlights = function(c)
        return {
          CursorLineNr = { fg = c.mauve, bold = true },
          LineNr = { fg = c.surface2 },
          CursorLine = { bg = "#21163a" },
          Visual = { bg = "#3b2d55" },
          Comment = { fg = c.overlay1, italic = true },
          -- диагностика: заметная, но не кричащая
          DiagnosticWarn = { fg = "#e8c88a" },
          DiagnosticVirtualTextWarn = { fg = "#a8916a", italic = true },
          DiagnosticVirtualTextError = { fg = "#c9718c", italic = true },
          DiagnosticVirtualTextInfo = { fg = c.overlay1, italic = true },
          DiagnosticVirtualTextHint = { fg = c.overlay1, italic = true },
          DiagnosticUnderlineWarn = { undercurl = true, sp = "#a8916a" },
          SnacksDashboardHeader = { fg = c.mauve },
          SnacksDashboardKey = { fg = c.pink },
          SnacksDashboardFooter = { fg = c.overlay0, italic = true },
        }
      end,
    },
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "catppuccin" } },
}

-- SQLFluff takes its dialect (ansi, postgres, snowflake, ...) from the nearest .sqlfluff file;
-- ~/.sqlfluff defaults to ansi. LazyVim's lang.sql extra hardcodes --dialect=ansi for formatting,
-- which overrides config files, so drop it. --stdin-filename makes SQLFluff resolve config as if
-- stdin were the buffer's file, so per-project .sqlfluff files apply to both lint and format.
return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters = opts.formatters or {}
      opts.formatters.sqlfluff = {
        args = { "format", "--stdin-filename", "$FILENAME", "-" },
      }
    end,
  },
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters = {
        sqlfluff = {
          args = {
            "lint",
            "--format=json",
            "--stdin-filename",
            function()
              return vim.api.nvim_buf_get_name(0)
            end,
            "-",
          },
        },
      },
    },
  },
}

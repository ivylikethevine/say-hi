-- hi's neovim override, kept to the minimum that earns the `-u`: neovim's own
-- defaults, minus what litters a target you are only visiting. Nothing to taste
-- lives here - your own $_HI_CONFIG_DIR/init.lua replaces this file wholesale.
--
-- Nothing of settings/vim.rc is repeated: that file exists to undo what `-u`
-- implies for vim (`compatible`) and to pull in defaults.vim, and neovim has
-- no compatible mode and ships every one of those defaults on already.
--
-- Line comments only. The payload strips `--` lines one at a time (GLOSSARY:
-- HI.35), so a `--[[` block would lose its opener and keep its body.

-- leave no droppings in a remote tree: no swap file beside the file you opened,
-- and no shada (marks, registers, command history) under the target's $HOME.
-- neovim writes both by default; backups and undo files it already does not.
vim.opt.swapfile = false
vim.opt.shadafile = "NONE"

local config = require("gitlab-issues.config")

local M = {}

local function set_keymap(lhs, rhs, desc)
	if not lhs or lhs == "" then
		return
	end

	vim.keymap.set("n", lhs, rhs, { desc = desc })
end

local function setup_keymaps(keymaps)
	if keymaps == false then
		return
	end

	keymaps = keymaps or {}

	set_keymap(keymaps.issues, function()
		M.issues()
	end, "GitLab Issues - all")

	set_keymap(keymaps.open_issues, function()
		M.issues({ state = "opened" })
	end, "GitLab Issues - open")

	set_keymap(keymaps.current_repo_open_issues, function()
		M.issues({
			current_repo = true,
			state = "opened",
		})
	end, "GitLab Issues - current repo open")

	set_keymap(keymaps.create_issue, function()
		M.create_issue()
	end, "GitLab Create Issue")
end

function M.setup(opts)
	local options = config.setup(opts)
	setup_keymaps(options.keymaps)
	return options
end

function M.get()
	return config.get()
end

function M.issues(opts)
	return require("gitlab-issues.picker").issues(opts)
end

function M.create_issue()
	return require("gitlab-issues.picker").create_issue()
end

return M

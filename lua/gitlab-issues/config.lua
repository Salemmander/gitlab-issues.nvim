local M = {}

M.defaults = {
	group = nil,
	gitlab_url = "https://gitlab.com",
	glab_cmd = "glab",
	keymaps = {
		issues = "<leader>GI",
		open_issues = "<leader>Go",
		current_repo_open_issues = "<leader>GO",
		create_issue = "<leader>GC",
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
	return M.options
end

function M.get()
	return M.options
end

function M.set_group(group)
	M.options.group = group
	return M.options
end

return M

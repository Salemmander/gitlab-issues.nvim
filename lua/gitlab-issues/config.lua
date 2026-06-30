local M = {}

M.defaults = {
	group = nil,
	gitlab_host = "gitlab.com",
	glab_cmd = "glab",
	keymaps = {
		issues = "<leader>GI",
		open_issues = "<leader>Go",
		current_repo_open_issues = "<leader>GO",
		create_issue = "<leader>GC",
	},
}

M.options = vim.deepcopy(M.defaults)

local function normalize_gitlab_host(host)
	if type(host) ~= "string" or host == "" then
		return nil, "gitlab_host must be a non-empty string"
	end

	host = host:gsub("^https?://", ""):gsub("/$", "")

	if host:find("/", 1, true) then
		return nil, "gitlab_host must be a hostname, not a URL path"
	end

	return host
end

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})

	local host, err = normalize_gitlab_host(M.options.gitlab_host)
	if err then
		vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
		M.options.gitlab_host = M.defaults.gitlab_host
	else
		M.options.gitlab_host = host
	end

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

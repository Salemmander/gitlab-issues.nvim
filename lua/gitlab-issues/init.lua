local config = require("gitlab-issues.config")

local M = {}

function M.setup(opts)
	return config.setup(opts)
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

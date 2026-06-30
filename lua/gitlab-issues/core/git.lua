local config = require("gitlab-issues.config")

local M = {}

function M.detect_repo()
	local cfg = config.get()

	local origin = vim.trim(vim.fn.system("git remote get-url origin 2>/dev/null"))
	local escaped_host = vim.pesc(cfg.gitlab_host)
	local repo = origin:match(escaped_host .. "[:/](.+)%.git$")

	if repo then
		return repo
	end

	return nil
end

return M

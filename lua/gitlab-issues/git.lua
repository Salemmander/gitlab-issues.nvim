local config = require("gitlab-issues.config")

local M = {}

function M.detect_repo()
	local cfg = config.get()
	if not cfg.group then
		return nil
	end

	local origin = vim.trim(vim.fn.system("git remote get-url origin 2>/dev/null"))
	local gitlab_host = (cfg.gitlab_url or ""):gsub("^https?://", ""):gsub("/$", "")
	local escaped_host = vim.pesc(gitlab_host)
	local repo = origin:match(escaped_host .. "[:/](.+)%.git$")

	if repo and vim.startswith(repo, cfg.group .. "/") then
		return repo
	end

	return nil
end

return M

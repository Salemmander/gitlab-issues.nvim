local backend = require("gitlab-issues.backend.glab")
local config = require("gitlab-issues.config")

local M = {}

function M.run(default_repo, on_created)
	local cfg = config.get()

	local function choose_repo(callback)
		if default_repo then
			callback(default_repo)
			return
		end

		backend.list_repos(cfg.group, function(repos, err)
			if err then
				vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
				return
			end
			if not repos or #repos == 0 then
				vim.notify("gitlab-issues: no repos found in " .. cfg.group, vim.log.levels.WARN)
				return
			end

			local all_repos = vim.deepcopy(repos)
			table.sort(all_repos)
			vim.ui.select(all_repos, { prompt = "Create issue in repo: " }, function(repo)
				if repo then
					callback(repo)
				end
			end)
		end)
	end

	choose_repo(function(repo)
		vim.ui.input({ prompt = "Issue title: " }, function(title)
			title = vim.trim(title or "")
			if title == "" then
				return
			end

			vim.ui.input({ prompt = "Description (optional): " }, function(desc)
				local chosen_repo = repo
				local chosen_title = title
				vim.notify("Creating issue in " .. chosen_repo .. "...", vim.log.levels.INFO)
				backend.create_issue(chosen_repo, chosen_title, desc, function(created, err)
					if err then
						vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
						return
					end

					vim.notify("Issue created: " .. created, vim.log.levels.INFO)
					if on_created then
						on_created()
					end
				end)
			end)
		end)
	end)
end

return M

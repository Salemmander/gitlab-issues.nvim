local backend = require("gitlab-issues.backend.glab")
local config = require("gitlab-issues.config")

local M = {}

function M.run(detected_repo, on_success)
	local cfg = config.get()

	backend.list_repos(function(all_repos, err)
		if err then
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			return
		end

		table.sort(all_repos)
		if detected_repo then
			for i, repo in ipairs(all_repos) do
				if repo == detected_repo then
					table.remove(all_repos, i)
					break
				end
			end
			table.insert(all_repos, 1, detected_repo)
		end

		if #all_repos == 0 then
			vim.notify("gitlab-issues: no repos found in " .. cfg.group, vim.log.levels.WARN)
			return
		end

		local chosen_repo
		local chosen_title

		vim.ui.select(all_repos, { prompt = "Create issue in repo: " }, function(repo)
			if not repo then
				return
			end

			chosen_repo = repo
			vim.ui.input({ prompt = "Title: " }, function(title)
				if not title or vim.trim(title) == "" then
					return
				end

				chosen_title = title
				vim.ui.input({ prompt = "Description (optional): " }, function(desc)
					vim.notify("Creating issue in " .. chosen_repo .. "...", vim.log.levels.INFO)
					backend.create_issue(chosen_repo, chosen_title, desc, function(created, err)
						if err then
							vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
							return
						end

						vim.notify("Issue created: " .. created, vim.log.levels.INFO)
						on_success()
					end)
				end)
			end)
		end)
	end)
end

return M

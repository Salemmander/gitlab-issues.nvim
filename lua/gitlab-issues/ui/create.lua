local backend = require("gitlab-issues.backend.glab")
local config = require("gitlab-issues.config")
local frontmatter = require("gitlab-issues.ui.frontmatter")
local scratch = require("gitlab-issues.ui.scratch")

local M = {}

local function is_submitting(win)
	return win and win.buf and vim.api.nvim_buf_is_valid(win.buf) and vim.b[win.buf].gitlab_issues_submitting
end

local function set_submitting(win, value)
	if win and win.buf and vim.api.nvim_buf_is_valid(win.buf) then
		vim.b[win.buf].gitlab_issues_submitting = value
	end
end

function M.submit(repo, win, on_created, ctx, close)
	if is_submitting(win) then
		return
	end

	local title, description = frontmatter.parse(win:text())
	if not title then
		return
	end

	set_submitting(win, true)
	vim.cmd.stopinsert()
	vim.notify("Creating issue in " .. repo .. "...", vim.log.levels.INFO)
	backend.create_issue(repo, title, description, function(created, err)
		if err then
			set_submitting(win, false)
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			return
		end

		vim.notify("Issue created: " .. created, vim.log.levels.INFO)
		close(win)
		if ctx and ctx.picker and not ctx.picker.closed then
			ctx.picker:focus()
		end
		if on_created then
			on_created()
		end
	end)
end

function M.open(repo, on_created, ctx)
	scratch.open({
		name = "Create issue in " .. repo,
		template = frontmatter.template(),
		filekey = repo .. "/issue/create",
		layout = "float",
		ctx = ctx,
		cursor = { 2, #"Title: " },
		on_submit = function(win, close)
			M.submit(repo, win, on_created, ctx, close)
		end,
	})
end

function M.run(default_repo, on_created, ctx)
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
		M.open(repo, on_created, ctx)
	end)
end

return M

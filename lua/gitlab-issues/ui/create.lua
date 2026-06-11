local backend = require("gitlab-issues.backend.glab")
local config = require("gitlab-issues.config")

local M = {}
local cleanup

local function parse(text)
	local title
	local body = text:gsub("^(%-%-%-\n.-\n%-%-%-\n%s*)", function(fm)
		fm = fm:gsub("^%-%-%-\n", ""):gsub("\n%-%-%-\n%s*$", "")
		for _, line in ipairs(vim.split(fm, "\n")) do
			local field, value = line:match("^(%w+):%s*(.-)%s*$")
			if field == "Title" then
				title = vim.trim(value or "")
			elseif field and field ~= "" then
				vim.notify(("gitlab-issues: unknown field `%s` in frontmatter"):format(field), vim.log.levels.WARN)
			end
		end
		return ""
	end)

	if not title or title == "" then
		vim.notify("gitlab-issues: missing required field `Title` in frontmatter", vim.log.levels.ERROR)
		return
	end

	return title, vim.trim(body)
end

local function scratch_opts(repo, on_created, ctx)
	local width = math.min(100, math.floor(vim.o.columns * 0.75))
	local height = math.min(18, math.floor(vim.o.lines * 0.45))

	return Snacks.win.resolve({
		relative = "editor",
		width = width,
		backdrop = false,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		border = "rounded",
		wo = { winhighlight = "NormalFloat:Normal,FloatTitle:SnacksGhScratchTitle,FloatBorder:SnacksGhScratchBorder" },
		on_win = function(win)
			vim.g.snacks_picker_cycle_win = win.win
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(win.win) and vim.api.nvim_buf_line_count(win.buf) >= 2 then
					pcall(vim.api.nvim_win_set_cursor, win.win, { 2, #"Title: " })
				end
				vim.cmd.startinsert()
			end)
		end,
		footer_keys = { "<c-s>", "<esc>" },
		keys = {
			cancel = {
				"<esc>",
				function(win)
					cleanup(win)
					if ctx and ctx.picker and not ctx.picker.closed then
						ctx.picker:focus()
					end
				end,
				desc = "Cancel",
				mode = "n",
			},
			submit = {
				"<c-s>",
				function(win)
					M.submit(repo, win, on_created, ctx)
				end,
				desc = "Submit",
				mode = { "n", "i" },
			},
		},
	})
end

function cleanup(win)
	local buf = win and win.buf
	local fname = buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) or nil

	if win then
		win:on("WinClosed", function()
			vim.schedule(function()
				if buf and vim.api.nvim_buf_is_valid(buf) then
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end
				if fname and fname ~= "" then
					os.remove(fname)
					os.remove(fname .. ".meta")
				end
			end)
		end, { buf = true })
		win:close()
	end
end

function M.submit(repo, win, on_created, ctx)
	local title, description = parse(win:text())
	if not title then
		return
	end

	vim.cmd.stopinsert()
	vim.notify("Creating issue in " .. repo .. "...", vim.log.levels.INFO)
	backend.create_issue(repo, title, description, function(created, err)
		if err then
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			return
		end

		vim.notify("Issue created: " .. created, vim.log.levels.INFO)
		cleanup(win)
		if ctx and ctx.picker and not ctx.picker.closed then
			ctx.picker:focus()
		end
		if on_created then
			on_created()
		end
	end)
end

function M.open(repo, on_created, ctx)
	Snacks.scratch({
		ft = "markdown",
		icon = " ",
		name = "Create issue in " .. repo,
		template = "---\nTitle: \n---\n\n",
		filekey = {
			cwd = false,
			branch = false,
			count = false,
			id = repo .. "/issue/create",
		},
		win = scratch_opts(repo, on_created, ctx),
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

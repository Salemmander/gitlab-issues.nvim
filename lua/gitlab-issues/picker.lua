local backend = require("gitlab-issues.backend.glab")
local config = require("gitlab-issues.config")
local create = require("gitlab-issues.create")
local git = require("gitlab-issues.git")
local issue = require("gitlab-issues.issue")

local M = {}

local KEYS = {
	{ key = "<C-o>", action = "view_issue", desc = "open" },
	{ key = "<C-e>", action = "assign_self", desc = "assign" },
	{ key = "<C-f>", action = "toggle_assignee", desc = "mine" },
	{ key = "<C-g>", action = "toggle_scope", desc = "scope" },
	{ key = "<C-s>", action = "toggle_state", desc = "state" },
	{ key = "<C-r>", action = "pick_repo", desc = "repo" },
	{ key = "<C-t>", action = "create_issue", desc = "new" },
	{ key = "<C-x>", action = "close_reopen", desc = "close/open" },
	{ key = "<C-b>", action = "add_comment", desc = "comment" },
}

local FOOTER = table.concat(
	vim.tbl_map(function(k)
		local letter = k.key:match("<C%-(.-)>")
		return "^" .. letter .. " " .. k.desc
	end, KEYS),
	"  "
)

local LAYOUT = {
	layout = {
		box = "vertical",
		width = 0.8,
		height = 0.7,
		border = true,
		title = "{title} {live} {flags}",
		title_pos = "center",
		footer = FOOTER,
		footer_pos = "center",
		{ win = "input", height = 1, border = "bottom" },
		{ win = "list", border = "none" },
		{ win = "preview", title = "{preview}", height = 0.7, border = "top" },
	},
}

local function input_keys()
	local keys = {}
	for _, entry in ipairs(KEYS) do
		keys[entry.key] = { entry.action, mode = { "i", "n" } }
	end
	return keys
end

local function open_comment_window(item)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = "markdown"
	vim.bo[buf].bufhidden = "wipe"

	local width = math.floor(vim.o.columns * 0.6)
	local height = 15
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		title = " Comment on #" .. item.iid .. ": " .. item.title .. " ",
		title_pos = "center",
		footer = " <C-s> submit  ·  <Esc> cancel ",
		footer_pos = "center",
		zindex = 250,
	})

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function submit()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local content = vim.trim(table.concat(lines, "\n"))
		if content == "" then
			vim.notify("gitlab-issues: comment is empty", vim.log.levels.WARN)
			return
		end

		close()
		vim.notify("Posting comment on #" .. item.iid .. "...", vim.log.levels.INFO)
		backend.add_comment(item, content, function(err)
			if err then
				vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
				return
			end

			vim.notify("Comment posted on #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
		end)
	end

	vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf })
	vim.keymap.set({ "n", "i" }, "<Esc>", close, { buffer = buf })
	vim.cmd("startinsert")
end

function M.issues(opts)
	opts = opts or {}

	local cfg = config.get()
	local detected_repo = git.detect_repo()
	local all_items = {}
	local assigned_only = false
	local repo_filter = nil
	local state_filter = opts.state
	local username = nil
	local pending = 2

	local function title_for()
		local scope = repo_filter and (repo_filter:match("[^/]+$") or repo_filter) or cfg.group
		local assignee = assigned_only and " (mine)" or ""
		local state = state_filter and " [" .. state_filter .. "]" or ""
		return "GitLab Issues [" .. scope .. "]" .. assignee .. state
	end

	local function compute_items()
		return issue.filter(all_items, {
			repo = repo_filter,
			assignee = assigned_only and username or nil,
			state = state_filter,
		})
	end

	local function apply_filter(picker)
		picker.opts.items = compute_items()
		picker.title = title_for()
		picker:find({ refresh = true })
	end

	local function refresh_item(picker, item, raw_issue)
		local new_item = issue.make_item(raw_issue)
		issue.replace(all_items, new_item)
		apply_filter(picker)
	end

	local function refetch_items(picker)
		backend.list_issues(function(raw_issues, err)
			if err then
				vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
				return
			end

			all_items = issue.make_items(raw_issues)
			apply_filter(picker)
		end)
	end

	local function open_picker()
		if pending > 0 then
			return
		end

		Snacks.picker({
			title = title_for(),
			layout = LAYOUT,
			items = compute_items(),
			format = function(item)
				if item.state == "closed" then
					return { { "✓ ", "DiagnosticInfo" }, { item.text, "Comment" } }
				end
				return { { "○ ", "DiagnosticOk" }, { item.text } }
			end,
			preview = issue.preview,
			actions = {
				view_issue = function(_, item)
					vim.ui.open(item.url)
				end,
				toggle_assignee = function(picker)
					if not username then
						vim.notify(
							"gitlab-issues: GitLab username unavailable; assignee filter has no effect",
							vim.log.levels.WARN
						)
						return
					end

					assigned_only = not assigned_only
					apply_filter(picker)
				end,
				toggle_scope = function(picker)
					if not detected_repo then
						vim.notify(
							"gitlab-issues: not in a " .. cfg.group .. " repo; scope filter unavailable",
							vim.log.levels.WARN
						)
						return
					end

					repo_filter = repo_filter == detected_repo and nil or detected_repo
					apply_filter(picker)
				end,
				toggle_state = function(picker)
					if state_filter == nil then
						state_filter = "opened"
					elseif state_filter == "opened" then
						state_filter = "closed"
					else
						state_filter = nil
					end

					apply_filter(picker)
				end,
				assign_self = function(picker, item)
					if not username then
						vim.notify("gitlab-issues: GitLab username unavailable", vim.log.levels.WARN)
						return
					end

					local is_assigned = vim.tbl_contains(item.assignee_usernames, username)
					local action_label = is_assigned and "Unassigned from" or "Assigned to"
					local pending_label = is_assigned and "Unassigning from" or "Assigning to"

					vim.notify(pending_label .. " #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
					backend.assign_issue(item, username, function(raw_issue, err)
						if err then
							vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
							return
						end

						refresh_item(picker, item, raw_issue)
						vim.notify(action_label .. " #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
					end)
				end,
				add_comment = function(_, item)
					open_comment_window(item)
				end,
				close_reopen = function(picker, item)
					local is_open = item.state == "opened"
					local action_word = is_open and "Close" or "Reopen"
					local done_label = is_open and "Closed" or "Reopened"

					vim.ui.select({ "No", "Yes" }, {
						prompt = action_word .. " #" .. item.iid .. ": " .. item.title .. "?",
					}, function(choice)
						if choice ~= "Yes" then
							return
						end

						vim.notify(action_word .. "ing #" .. item.iid .. "...", vim.log.levels.INFO)
						backend.close_or_reopen_issue(item, function(raw_issue, err)
							if err then
								vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
								return
							end

							refresh_item(picker, item, raw_issue)
							vim.notify(done_label .. " #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
						end)
					end)
				end,
				create_issue = function(picker)
					create.run(detected_repo, function()
						refetch_items(picker)
					end)
				end,
				pick_repo = function(picker)
					vim.ui.select(issue.repos_from_items(all_items), { prompt = "Filter by repo: " }, function(choice)
						if not choice then
							return
						end

						repo_filter = choice == "All repos" and nil or choice
						apply_filter(picker)
					end)
				end,
			},
			win = {
				input = {
					keys = input_keys(),
				},
			},
		})

		backend.list_repos(function() end)
	end

	backend.current_user(function(resolved_username, err)
		if resolved_username then
			username = resolved_username
		else
			vim.notify("gitlab-issues: " .. (err or "could not resolve GitLab username"), vim.log.levels.WARN)
		end

		pending = pending - 1
		open_picker()
	end)

	backend.list_issues(function(raw_issues, err)
		if err then
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			pending = math.huge
			return
		end

		all_items = issue.make_items(raw_issues)
		pending = pending - 1
		open_picker()
	end)
end

function M.create_issue()
	create.run(git.detect_repo(), function() end)
end

return M

local backend = require("gitlab-issues.backend.glab")
local action_factory = require("gitlab-issues.ui.actions")
local config = require("gitlab-issues.config")
local create = require("gitlab-issues.ui.create")
local git = require("gitlab-issues.core.git")
local issue = require("gitlab-issues.core.issue")
local layout = require("gitlab-issues.ui.layout")
local preview = require("gitlab-issues.ui.preview")

local M = {}

function M.issues(opts)
	opts = opts or {}

	local cfg = config.get()
	local state = {
		active_group = opts.group ~= nil and opts.group or cfg.group,
		all_items = {},
		assigned_only = false,
		detected_repo = git.detect_repo(),
		repo_filter = opts.repo,
		state_filter = opts.state,
		username = nil,
		pending = 2,
	}

	if opts.current_repo and not state.detected_repo then
		vim.notify("gitlab-issues: current repo scope filter unavailable", vim.log.levels.WARN)
		return
	end

	if opts.current_repo then
		state.repo_filter = state.detected_repo
	end

	local function title_for()
		local base_scope = state.active_group or "all visible"
		local scope = state.repo_filter and (state.repo_filter:match("[^/]+$") or state.repo_filter) or base_scope
		local assignee = state.assigned_only and " (mine)" or ""
		local filter_state = state.state_filter and " [" .. state.state_filter .. "]" or ""
		return "GitLab Issues [" .. scope .. "]" .. assignee .. filter_state
	end

	local function compute_items()
		return issue.filter(state.all_items, {
			repo = state.repo_filter,
			assignee = state.assigned_only and state.username or nil,
			state = state.state_filter,
		})
	end

	local function apply_filter(picker)
		local items = compute_items()
		picker.opts.items = items
		picker.title = title_for()
		picker:find({ refresh = true })
		preview.prefetch(items, 25)
	end

	local function refresh_item(picker, item, raw_issue)
		local new_item = issue.make_item(raw_issue)
		issue.replace(state.all_items, new_item)
		apply_filter(picker)
	end

	local function refetch_items(picker)
		backend.list_issues(state.active_group, function(raw_issues, err)
			if err then
				vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
				return
			end

			state.all_items = issue.make_items(raw_issues)
			apply_filter(picker)
		end)
	end

	local function open_picker()
		if state.pending > 0 then
			return
		end

		local actions = action_factory.build({
			state = state,
			apply_filter = apply_filter,
			refresh_item = refresh_item,
			refetch_items = refetch_items,
		})

		Snacks.picker({
			title = title_for(),
			layout = layout.picker,
			items = compute_items(),
			format = layout.format,
			preview = issue.preview,
			confirm = "issue_actions",
			actions = actions,
			win = {
				input = {
					keys = layout.input_keys(),
				},
			},
		})

		preview.prefetch(compute_items(), 25)

		if state.active_group then
			backend.list_repos(state.active_group, function() end)
		end
	end

	backend.current_user(function(resolved_username, err)
		if resolved_username then
			state.username = resolved_username
		else
			vim.notify("gitlab-issues: " .. (err or "could not resolve GitLab username"), vim.log.levels.WARN)
		end

		state.pending = state.pending - 1
		open_picker()
	end)

	backend.list_issues(state.active_group, function(raw_issues, err)
		if err then
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			state.pending = math.huge
			return
		end

		state.all_items = issue.make_items(raw_issues)
		state.pending = state.pending - 1
		open_picker()
	end)
end

function M.create_issue()
	create.run(git.detect_repo(), function() end)
end

return M

local backend = require("gitlab-issues.backend.glab")
local comment = require("gitlab-issues.ui.comment")
local config = require("gitlab-issues.config")
local create = require("gitlab-issues.ui.create")
local edit = require("gitlab-issues.ui.edit")
local git = require("gitlab-issues.core.git")
local issue = require("gitlab-issues.core.issue")
local labels = require("gitlab-issues.ui.labels")
local layout = require("gitlab-issues.ui.layout")

local M = {}

local function notify_error(err)
	vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
end

local function add_menu_item(items, name, desc, icon)
	local number = #items + 1
	items[#items + 1] = {
		text = tostring(number) .. ". " .. desc,
		desc = desc,
		icon = icon,
		name = name,
	}
end

local function action_layout(count)
	return vim.tbl_deep_extend("force", layout.actions_picker.layout, {
		config = function(action_layout_config)
			for _, box in ipairs(action_layout_config.layout) do
				if box.win == "list" and not box.height then
					box.height = math.max(math.min(count, vim.o.lines * 0.8 - 10), 3)
				end
			end
		end,
	})
end

function M.build(ctx)
	local state = ctx.state
	local actions = {}

	local function open_action_menu(picker, item)
		if not item then
			return
		end

		local menu_items = {}
		if state.username then
			local assign_label = vim.tbl_contains(item.assignee_usernames, state.username) and "Unassign yourself"
				or "Assign yourself"
			add_menu_item(menu_items, "assign_self", assign_label .. " on issue #" .. item.iid, " ")
		end

		add_menu_item(menu_items, "add_comment", "Comment on issue #" .. item.iid, " ")
		add_menu_item(menu_items, "edit_issue", "Edit issue #" .. item.iid, " ")
		add_menu_item(menu_items, "edit_labels", "Edit labels on issue #" .. item.iid, " ")
		add_menu_item(menu_items, "view_issue", "Open issue #" .. item.iid .. " in browser", " ")

		local close_label = item.state == "opened" and "Close issue" or "Reopen issue"
		add_menu_item(menu_items, "close_reopen", close_label .. " #" .. item.iid, " ")

		Snacks.picker({
			title = "GitLab Actions",
			layout = action_layout(#menu_items),
			items = menu_items,
			format = layout.format_action,
			confirm = function(action_picker, action_item)
				if not action_item then
					return
				end

				picker:focus()
				actions[action_item.name](picker, item)
				action_picker:close()
			end,
		})
	end

	actions.issue_actions = open_action_menu

	actions.view_issue = function(_, item)
		vim.ui.open(item.url)
	end

	actions.toggle_assignee = function(picker)
		if not state.username then
			vim.notify("gitlab-issues: GitLab username unavailable; assignee filter has no effect", vim.log.levels.WARN)
			return
		end

		state.assigned_only = not state.assigned_only
		ctx.apply_filter(picker)
	end

	actions.toggle_scope = function(picker)
		if not state.detected_repo then
			vim.notify("gitlab-issues: current repo scope filter unavailable", vim.log.levels.WARN)
			return
		end

		state.repo_filter = state.repo_filter == state.detected_repo and nil or state.detected_repo
		ctx.apply_filter(picker)
	end

	actions.toggle_state = function(picker)
		if state.state_filter == nil then
			state.state_filter = "opened"
		elseif state.state_filter == "opened" then
			state.state_filter = "closed"
		else
			state.state_filter = nil
		end

		ctx.apply_filter(picker)
	end

	actions.assign_self = function(picker, item)
		if not state.username then
			vim.notify("gitlab-issues: GitLab username unavailable", vim.log.levels.WARN)
			return
		end

		local is_assigned = vim.tbl_contains(item.assignee_usernames, state.username)
		local action_label = is_assigned and "Unassigned from" or "Assigned to"
		local pending_label = is_assigned and "Unassigning from" or "Assigning to"

		vim.notify(pending_label .. " #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
		backend.assign_issue(item, state.username, function(raw_issue, err)
			if err then
				notify_error(err)
				return
			end

			ctx.refresh_item(picker, item, raw_issue)
			vim.notify(action_label .. " #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
		end)
	end

	actions.add_comment = function(picker, item)
		comment.open(item, { picker = picker })
	end

	actions.edit_issue = function(picker, item)
		edit.open(item, { picker = picker, refresh_item = ctx.refresh_item })
	end

	actions.edit_labels = function(picker, item)
		labels.open(item, { picker = picker, refresh_item = ctx.refresh_item })
	end

	actions.close_reopen = function(picker, item)
		local is_open = item.state == "opened"
		local action_word = is_open and "Clos" or "Reopen"
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
					notify_error(err)
					return
				end

				ctx.refresh_item(picker, item, raw_issue)
				vim.notify(done_label .. " #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
			end)
		end)
	end

	actions.create_issue = function(picker)
		create.run(state.detected_repo, function()
			ctx.refetch_items(picker)
		end, { picker = picker })
	end

	actions.pick_repo = function(picker)
		vim.ui.select(issue.repos_from_items(state.all_items), { prompt = "Filter by repo: " }, function(choice)
			if not choice then
				return
			end

			if choice == "All repos" then
				state.repo_filter = nil
			else
				state.repo_filter = choice
			end
			ctx.apply_filter(picker)
		end)
	end

	actions.pick_group = function(picker)
		backend.list_groups(function(groups, err)
			if err then
				notify_error(err)
				return
			end

			local choices = { "All visible issues" }
			for _, group in ipairs(groups) do
				if type(group.full_path) == "string" then
					choices[#choices + 1] = group.full_path
				end
			end

			vim.ui.select(choices, { prompt = "Default group: " }, function(choice)
				if not choice then
					return
				end

				if choice == "All visible issues" then
					state.active_group = nil
				else
					state.active_group = choice
				end
				config.set_group(state.active_group)
				state.detected_repo = git.detect_repo()
				state.repo_filter = nil
				ctx.refetch_items(picker)
			end)
		end)
	end

	return actions
end

return M

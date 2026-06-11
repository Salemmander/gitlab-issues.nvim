local backend = require("gitlab-issues.backend.glab")
local comment = require("gitlab-issues.comment")
local config = require("gitlab-issues.config")
local create = require("gitlab-issues.create")
local git = require("gitlab-issues.git")
local issue = require("gitlab-issues.issue")
local layout = require("gitlab-issues.layout")

local M = {}

function M.issues(opts)
	opts = opts or {}

	local cfg = config.get()
	local active_group = opts.group ~= nil and opts.group or cfg.group
	local detected_repo = git.detect_repo()
	if opts.current_repo and not detected_repo then
		vim.notify("gitlab-issues: current repo scope filter unavailable", vim.log.levels.WARN)
		return
	end

	local all_items = {}
	local assigned_only = false
	local repo_filter = opts.current_repo and detected_repo or opts.repo
	local state_filter = opts.state
	local username = nil
	local pending = 2

	local function title_for()
		local base_scope = active_group or "all visible"
		local scope = repo_filter and (repo_filter:match("[^/]+$") or repo_filter) or base_scope
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
		backend.list_issues(active_group, function(raw_issues, err)
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

		local actions = {}
		local menu_items = {}

		local function add_menu_item(name, desc, icon)
			local number = #menu_items + 1
			menu_items[#menu_items + 1] = {
				text = tostring(number) .. ". " .. desc,
				desc = desc,
				icon = icon,
				name = name,
			}
		end

		local function open_action_menu(picker, item)
			if not item then
				return
			end

			menu_items = {}
			if username then
				local assign_label = vim.tbl_contains(item.assignee_usernames, username) and "Unassign yourself"
					or "Assign yourself"
				add_menu_item("assign_self", assign_label .. " on issue #" .. item.iid, " ")
			end

			add_menu_item("add_comment", "Comment on issue #" .. item.iid, " ")
			add_menu_item("view_issue", "Open issue #" .. item.iid .. " in browser", " ")

			local close_label = item.state == "opened" and "Close issue" or "Reopen issue"
			add_menu_item("close_reopen", close_label .. " #" .. item.iid, " ")

			Snacks.picker({
				title = "GitLab Actions",
				layout = vim.tbl_deep_extend("force", layout.actions_picker.layout, {
					config = function(action_layout)
						for _, box in ipairs(action_layout.layout) do
							if box.win == "list" and not box.height then
								box.height = math.max(math.min(#menu_items, vim.o.lines * 0.8 - 10), 3)
							end
						end
					end,
				}),
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
			if not username then
				vim.notify(
					"gitlab-issues: GitLab username unavailable; assignee filter has no effect",
					vim.log.levels.WARN
				)
				return
			end

			assigned_only = not assigned_only
			apply_filter(picker)
		end

		actions.toggle_scope = function(picker)
			if not detected_repo then
				vim.notify("gitlab-issues: current repo scope filter unavailable", vim.log.levels.WARN)
				return
			end

			if repo_filter == detected_repo then
				repo_filter = nil
			else
				repo_filter = detected_repo
			end
			apply_filter(picker)
		end

		actions.toggle_state = function(picker)
			if state_filter == nil then
				state_filter = "opened"
			elseif state_filter == "opened" then
				state_filter = "closed"
			else
				state_filter = nil
			end

			apply_filter(picker)
		end

		actions.assign_self = function(picker, item)
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
		end

		actions.add_comment = function(_, item)
			comment.open(item)
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
						vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
						return
					end

					refresh_item(picker, item, raw_issue)
					vim.notify(done_label .. " #" .. item.iid .. ": " .. item.title, vim.log.levels.INFO)
				end)
			end)
		end

		actions.create_issue = function(picker)
			create.run(detected_repo, function()
				refetch_items(picker)
			end)
		end

		actions.pick_repo = function(picker)
			vim.ui.select(issue.repos_from_items(all_items), { prompt = "Filter by repo: " }, function(choice)
				if not choice then
					return
				end

				if choice == "All repos" then
					repo_filter = nil
				else
					repo_filter = choice
				end
				apply_filter(picker)
			end)
		end

		actions.pick_group = function(picker)
			backend.list_groups(function(groups, err)
				if err then
					vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
					return
				end

				local choices = { "All visible issues" }
				for _, group in ipairs(groups) do
					if type(group.full_path) == "string" then
						table.insert(choices, group.full_path)
					end
				end

				vim.ui.select(choices, { prompt = "Default group: " }, function(choice)
					if not choice then
						return
					end

					if choice == "All visible issues" then
						active_group = nil
					else
						active_group = choice
					end

					config.set_group(active_group)
					detected_repo = git.detect_repo()
					repo_filter = nil
					refetch_items(picker)
				end)
			end)
		end

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

		if active_group then
			backend.list_repos(active_group, function() end)
		end
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

	backend.list_issues(active_group, function(raw_issues, err)
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

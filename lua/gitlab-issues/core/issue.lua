local M = {}

M.preview = require("gitlab-issues.ui.preview").render

function M.filter(items, opts)
	return vim.tbl_filter(function(item)
		if opts.repo and item.repo ~= opts.repo then
			return false
		end
		if opts.assignee and not vim.tbl_contains(item.assignee_usernames, opts.assignee) then
			return false
		end
		if opts.state and item.state ~= opts.state then
			return false
		end
		return true
	end, items)
end

local function get_assignees(issue)
	return table.concat(
		vim.tbl_map(function(a)
			return a.name
		end, issue.assignees or {}),
		", "
	)
end

local function get_assignee_usernames(issue)
	return vim.tbl_map(function(a)
		return a.username
	end, issue.assignees or {})
end

local function get_labels(issue)
	return table.concat(
		vim.tbl_map(function(l)
			return type(l) == "string" and l or l.name
		end, issue.labels or {}),
		", "
	)
end

local function get_label_details(issue)
	return vim.tbl_filter(function(label)
		return type(label) == "table" and type(label.name) == "string"
	end, issue.labels or {})
end

function M.make_item(raw_issue)
	local repo = raw_issue.references and (raw_issue.references.full or ""):match("(.+)#%d+") or ""
	return {
		text = string.format("#%-5d %s", raw_issue.iid, raw_issue.title),
		iid = raw_issue.iid,
		repo = repo or "",
		title = raw_issue.title,
		state = raw_issue.state,
		author = raw_issue.author and raw_issue.author.name or "",
		assignees = get_assignees(raw_issue),
		assignee_usernames = get_assignee_usernames(raw_issue),
		labels = get_labels(raw_issue),
		label_details = get_label_details(raw_issue),
		created_at = raw_issue.created_at,
		updated_at = raw_issue.updated_at,
		closed_at = raw_issue.closed_at,
		description = raw_issue.description or "",
		url = raw_issue.web_url or "",
	}
end

function M.make_items(raw_issues)
	return vim.tbl_map(M.make_item, raw_issues or {})
end

function M.replace(items, new_item)
	for idx, item in ipairs(items) do
		if item.iid == new_item.iid and item.repo == new_item.repo then
			items[idx] = new_item
			return
		end
	end
end

function M.repos_from_items(items)
	local seen = {}
	local repos = {}

	for _, item in ipairs(items) do
		if item.repo ~= "" and not seen[item.repo] then
			seen[item.repo] = true
			table.insert(repos, item.repo)
		end
	end

	table.sort(repos)
	table.insert(repos, 1, "All repos")

	return repos
end

return M

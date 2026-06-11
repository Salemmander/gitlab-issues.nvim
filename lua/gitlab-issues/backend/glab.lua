local config = require("gitlab-issues.config")

local M = {}

local repo_cache = nil
local repo_cache_group = nil
local group_cache = nil
local label_cache = {}

local function run(args, callback)
	local cfg = config.get()
	vim.system(vim.list_extend({ cfg.glab_cmd }, args), { text = true }, function(out)
		vim.schedule(function()
			callback(out)
		end)
	end)
end

local function decode(out)
	local ok, decoded = pcall(vim.json.decode, out.stdout)
	if ok then
		return decoded
	end
	return nil
end

local function group_required(group, callback)
	local cfg = config.get()
	group = group or cfg.group
	if group then
		return group
	end

	callback(nil, "`group` is required")
	return nil
end

function M.current_user(callback)
	run({ "api", "user", "--output", "json" }, function(out)
		local user = decode(out)
		if type(user) == "table" and type(user.username) == "string" then
			callback(user.username)
		else
			callback(nil, out.stderr or "could not resolve GitLab username")
		end
	end)
end

function M.list_groups(callback)
	if group_cache then
		callback(group_cache)
		return
	end

	run({ "api", "groups", "--paginate" }, function(out)
		local groups = decode(out)
		if type(groups) ~= "table" then
			callback(nil, out.stderr or "failed to fetch groups")
			return
		end

		group_cache = groups
		callback(groups)
	end)
end

function M.list_repos(group, callback)
	if type(group) == "function" then
		callback = group
		group = nil
	end

	group = group_required(group, callback)
	if not group then
		return
	end

	if repo_cache and repo_cache_group == group then
		callback(repo_cache)
		return
	end

	local accumulated = {}

	local function fetch_page(page)
		local url = "groups/" .. group .. "/projects?include_subgroups=true&per_page=100&page=" .. page
		run({ "api", url }, function(out)
			local projects = decode(out)
			if type(projects) ~= "table" then
				callback(nil, out.stderr or "failed to fetch repos")
				return
			end

			for _, project in ipairs(projects) do
				if type(project.path_with_namespace) == "string" then
					table.insert(accumulated, project.path_with_namespace)
				end
			end

			if #projects == 100 then
				fetch_page(page + 1)
			else
				repo_cache = accumulated
				repo_cache_group = group
				callback(accumulated)
			end
		end)
	end

	fetch_page(1)
end

function M.list_issues(group, callback)
	if type(group) == "function" then
		callback = group
		group = nil
	end

	local args = group and { "issue", "list", "-g", group, "-O", "json", "--all" } or { "api", "issues", "--paginate" }

	run(args, function(out)
		local issues = decode(out)
		if type(issues) ~= "table" then
			callback(nil, out.stderr or out.stdout or "failed to fetch issues")
			return
		end

		callback(issues)
	end)
end

function M.fetch_issue(item, callback)
	local encoded_repo = item.repo:gsub("/", "%%2F")
	local api_path = "projects/" .. encoded_repo .. "/issues/" .. tostring(item.iid)

	run({ "api", api_path }, function(out)
		local raw_issue = decode(out)
		if type(raw_issue) ~= "table" then
			callback(nil, out.stderr or "failed to fetch issue")
			return
		end

		callback(raw_issue)
	end)
end

function M.assign_issue(item, username, callback)
	local is_assigned = vim.tbl_contains(item.assignee_usernames, username)
	local prefix = is_assigned and "-" or "+"

	run({ "issue", "update", tostring(item.iid), "-R", item.repo, "--assignee", prefix .. username }, function(out)
		if out.code ~= 0 then
			callback(nil, out.stderr or "update failed")
			return
		end

		M.fetch_issue(item, callback)
	end)
end

function M.add_comment(item, content, callback)
	run({ "issue", "note", tostring(item.iid), "-R", item.repo, "-m", content }, function(out)
		if out.code ~= 0 then
			callback(nil, out.stderr or "comment failed")
			return
		end

		callback(true)
	end)
end

function M.list_comments(item, callback)
	local encoded_repo = item.repo:gsub("/", "%%2F")
	local api_path = "projects/" .. encoded_repo .. "/issues/" .. tostring(item.iid) .. "/notes?per_page=100"

	run({ "api", api_path, "--paginate" }, function(out)
		local comments = decode(out)
		if type(comments) ~= "table" then
			callback(nil, out.stderr or "failed to fetch comments")
			return
		end

		callback(comments)
	end)
end

function M.list_labels(repo, callback)
	if label_cache[repo] then
		callback(label_cache[repo])
		return
	end

	local encoded_repo = repo:gsub("/", "%%2F")
	local api_path = "projects/" .. encoded_repo .. "/labels?per_page=100"

	run({ "api", api_path, "--paginate" }, function(out)
		local labels = decode(out)
		if type(labels) ~= "table" then
			callback(nil, out.stderr or "failed to fetch labels")
			return
		end

		label_cache[repo] = labels
		callback(labels)
	end)
end

function M.labels_cached(repo)
	return label_cache[repo] ~= nil
end

function M.prefetch_labels(repos, limit)
	local seen = {}
	local count = 0

	for _, repo in ipairs(repos or {}) do
		if repo ~= "" and not seen[repo] then
			seen[repo] = true
			count = count + 1
			if limit and count > limit then
				break
			end

			M.list_labels(repo, function() end)
		end
	end
end

function M.update_issue_labels(item, add, remove, callback)
	local args = {
		"issue",
		"update",
		tostring(item.iid),
		"-R",
		item.repo,
	}

	if #add > 0 then
		vim.list_extend(args, { "--label", table.concat(add, ",") })
	end
	if #remove > 0 then
		vim.list_extend(args, { "--unlabel", table.concat(remove, ",") })
	end

	run(args, function(out)
		if out.code ~= 0 then
			callback(nil, out.stderr or "update labels failed")
			return
		end

		M.fetch_issue(item, callback)
	end)
end

function M.close_or_reopen_issue(item, callback)
	local cmd_verb = item.state == "opened" and "close" or "reopen"

	run({ "issue", cmd_verb, tostring(item.iid), "-R", item.repo }, function(out)
		if out.code ~= 0 then
			callback(nil, out.stderr or cmd_verb .. " failed")
			return
		end

		M.fetch_issue(item, callback)
	end)
end

function M.create_issue(repo, title, description, callback)
	run({
		"issue",
		"create",
		"-R",
		repo,
		"--title",
		title,
		"--description",
		description or "",
	}, function(out)
		if out.code ~= 0 then
			callback(nil, out.stderr or "create failed")
			return
		end

		callback(vim.trim(out.stdout))
	end)
end

function M.update_issue(item, title, description, callback)
	run({
		"issue",
		"update",
		tostring(item.iid),
		"-R",
		item.repo,
		"--title",
		title,
		"--description",
		description or "",
	}, function(out)
		if out.code ~= 0 then
			callback(nil, out.stderr or "update failed")
			return
		end

		M.fetch_issue(item, callback)
	end)
end

return M

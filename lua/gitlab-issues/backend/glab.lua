local config = require("gitlab-issues.config")

local M = {}

local repo_cache = nil
local repo_cache_group = nil

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

local function group_required(callback)
	local cfg = config.get()
	if cfg.group then
		return cfg
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

function M.list_repos(callback)
	local cfg = group_required(callback)
	if not cfg then
		return
	end

	if repo_cache and repo_cache_group == cfg.group then
		callback(repo_cache)
		return
	end

	local accumulated = {}

	local function fetch_page(page)
		local url = "groups/" .. cfg.group .. "/projects?include_subgroups=true&per_page=100&page=" .. page
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
				repo_cache_group = cfg.group
				callback(accumulated)
			end
		end)
	end

	fetch_page(1)
end

function M.list_issues(callback)
	local cfg = group_required(callback)
	if not cfg then
		return
	end

	run({ "issue", "list", "-g", cfg.group, "-O", "json", "--all" }, function(out)
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
			callback(out.stderr or "comment failed")
			return
		end

		callback()
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

return M

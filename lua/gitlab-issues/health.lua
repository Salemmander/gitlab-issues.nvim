local config = require("gitlab-issues.config")

local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error
local info = vim.health.info or vim.health.report_info

local function run(command)
	return vim.system(command, { text = true }):wait()
end

local function check_snacks()
	local loaded = pcall(require, "snacks")
	if loaded then
		ok("snacks.nvim is available")
	else
		error("snacks.nvim is not available")
	end
end

local function check_glab(cfg)
	if vim.fn.executable(cfg.glab_cmd) ~= 1 then
		error(("`%s` is not executable"):format(cfg.glab_cmd))
		return
	end

	ok(("`%s` is executable"):format(cfg.glab_cmd))

	local auth = run({ cfg.glab_cmd, "auth", "status", "--hostname", cfg.gitlab_host })
	if auth.code == 0 then
		ok(("glab authentication is configured for %s"):format(cfg.gitlab_host))
	else
		error("glab authentication failed", {
			("Run `glab auth login --hostname %s`."):format(cfg.gitlab_host),
			vim.trim(auth.stderr ~= "" and auth.stderr or auth.stdout),
		})
	end
end

local function check_config(cfg)
	info(("gitlab_host: %s"):format(cfg.gitlab_host))
	info(("glab_cmd: %s"):format(cfg.glab_cmd))

	if cfg.group then
		info(("default group: %s"):format(cfg.group))
	else
		warn("No default group configured; picker will use all issues visible to glab")
	end

	if cfg.keymaps == false then
		info("default keymaps: disabled")
	else
		info("default keymaps: enabled")
	end
end

function M.check()
	local cfg = config.get()

	start("gitlab-issues.nvim")
	check_config(cfg)

	start("Dependencies")
	check_snacks()
	check_glab(cfg)
end

return M

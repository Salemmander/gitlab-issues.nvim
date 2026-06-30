local backend = require("gitlab-issues.backend.glab")
local preview = require("gitlab-issues.ui.preview")
local scratch = require("gitlab-issues.ui.scratch")
local submit = require("gitlab-issues.ui.submit")

local M = {}

function M.submit(item, win, ctx, close)
	if submit.is_submitting(win) then
		return
	end

	local content = vim.trim(win:text())
	if content == "" then
		vim.notify("gitlab-issues: comment is empty", vim.log.levels.WARN)
		return
	end

	submit.set_submitting(win, true)
	vim.cmd.stopinsert()
	vim.notify("Posting comment on #" .. item.iid .. "...", vim.log.levels.INFO)
	backend.add_comment(item, content, function(_, err)
		if err then
			submit.set_submitting(win, false)
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			return
		end

		vim.notify("Comment posted on #" .. item.iid, vim.log.levels.INFO)
		item._comments = nil
		item._comments_error = nil
		item._comments_loading = false
		close(win)
		if ctx and ctx.picker and not ctx.picker.closed then
			ctx.picker:focus()
			preview.refresh(ctx.picker)
		end
	end)
end

function M.open(item, ctx)
	scratch.open({
		name = "Comment on issue #" .. item.iid,
		template = "",
		filekey = item.repo .. "/issue/" .. tostring(item.iid) .. "/comment",
		ctx = ctx,
		height = 10,
		on_submit = function(win, close)
			M.submit(item, win, ctx, close)
		end,
	})
end

return M

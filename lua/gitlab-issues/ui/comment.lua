local backend = require("gitlab-issues.backend.glab")

local M = {}
local cleanup

local function parent_win(ctx)
	local picker = ctx and ctx.picker
	local preview = picker and picker.preview and picker.preview.win
	if preview and preview.valid and preview:valid() then
		return preview.win
	end

	return vim.api.nvim_get_current_win()
end

local function scratch_opts(item, ctx)
	local parent = parent_win(ctx)
	local height = 10

	return Snacks.win.resolve({
		relative = "win",
		width = 0,
		backdrop = false,
		height = height,
		win = parent,
		border = "top_bottom",
		wo = { winhighlight = "NormalFloat:Normal,FloatTitle:SnacksGhScratchTitle,FloatBorder:SnacksGhScratchBorder" },
		row = function(win)
			local border = win:border_size()
			return win:parent_size().height - height - border.top - border.bottom
		end,
		on_win = function(win)
			if vim.api.nvim_win_is_valid(parent) then
				local parent_row = vim.api.nvim_win_call(parent, vim.fn.winline)
				parent_row = parent_row + vim.wo[parent].scrolloff
				local row = vim.api.nvim_win_get_height(parent) - win:size().height
				if parent_row > row then
					vim.api.nvim_win_call(parent, function()
						vim.cmd(("normal! %d%s"):format(parent_row - row, Snacks.util.keycode("<C-e>")))
					end)
				end
			end

			vim.g.snacks_picker_cycle_win = win.win
			vim.schedule(function()
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
					M.submit(item, win, ctx)
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

function M.submit(item, win, ctx)
	local content = vim.trim(win:text())
	if content == "" then
		vim.notify("gitlab-issues: comment is empty", vim.log.levels.WARN)
		return
	end

	vim.cmd.stopinsert()
	vim.notify("Posting comment on #" .. item.iid .. "...", vim.log.levels.INFO)
	backend.add_comment(item, content, function(_, err)
		if err then
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			return
		end

		vim.notify("Comment posted on #" .. item.iid, vim.log.levels.INFO)
		cleanup(win)
		if ctx and ctx.picker and not ctx.picker.closed then
			ctx.picker:focus()
		end
	end)
end

function M.open(item, ctx)
	Snacks.scratch({
		ft = "markdown",
		icon = " ",
		name = "Comment on issue #" .. item.iid,
		template = "",
		filekey = {
			cwd = false,
			branch = false,
			count = false,
			id = item.repo .. "/issue/" .. tostring(item.iid) .. "/comment",
		},
		win = scratch_opts(item, ctx),
	})
end

return M

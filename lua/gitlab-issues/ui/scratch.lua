local M = {}

local function picker_parent(ctx)
	local picker = ctx and ctx.picker
	local preview = picker and picker.preview and picker.preview.win
	if preview and preview.valid and preview:valid() then
		return preview.win
	end

	return vim.api.nvim_get_current_win()
end

local function focus_picker(ctx)
	if ctx and ctx.picker and not ctx.picker.closed then
		ctx.picker:focus()
	end
end

function M.close(win)
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

local function start_insert(win, cursor)
	vim.schedule(function()
		if cursor and vim.api.nvim_win_is_valid(win.win) and vim.api.nvim_buf_line_count(win.buf) >= cursor[1] then
			pcall(vim.api.nvim_win_set_cursor, win.win, cursor)
		end
		vim.cmd.startinsert()
	end)
end

local function picker_win_opts(opts)
	local parent = picker_parent(opts.ctx)
	local height = opts.height or 10

	return {
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
			start_insert(win, opts.cursor)
		end,
	}
end

local function floating_win_opts(opts)
	local width = opts.width or math.min(100, math.floor(vim.o.columns * 0.75))
	local height = opts.height or math.min(18, math.floor(vim.o.lines * 0.45))

	return {
		relative = "editor",
		width = width,
		backdrop = false,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - height) / 2),
		border = "rounded",
		wo = { winhighlight = "NormalFloat:Normal,FloatTitle:SnacksGhScratchTitle,FloatBorder:SnacksGhScratchBorder" },
		on_win = function(win)
			vim.g.snacks_picker_cycle_win = win.win
			start_insert(win, opts.cursor)
		end,
	}
end

local function win_opts(opts)
	local base = opts.layout == "float" and floating_win_opts(opts) or picker_win_opts(opts)

	return Snacks.win.resolve(vim.tbl_deep_extend("force", base, {
		footer_keys = { "<c-s>", "<esc>" },
		keys = {
			cancel = {
				"<esc>",
				function(win)
					M.close(win)
					focus_picker(opts.ctx)
				end,
				desc = "Cancel",
				mode = "n",
			},
			submit = {
				"<c-s>",
				function(win)
					opts.on_submit(win, M.close)
				end,
				desc = "Submit",
				mode = { "n", "i" },
			},
		},
	}))
end

function M.open(opts)
	Snacks.scratch({
		ft = "markdown",
		icon = opts.icon or " ",
		name = opts.name,
		template = opts.template or "",
		filekey = {
			cwd = false,
			branch = false,
			count = false,
			id = opts.filekey,
		},
		win = win_opts(opts),
	})
end

return M

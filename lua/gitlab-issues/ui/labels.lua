local backend = require("gitlab-issues.backend.glab")

local M = {}

local function label_set(item)
	local set = {}
	if item.labels == "" then
		return set
	end

	for _, label in ipairs(vim.split(item.labels, ",", { plain = true, trimempty = true })) do
		set[vim.trim(label)] = true
	end

	return set
end

local function label_items(labels)
	table.sort(labels, function(a, b)
		return (a.name or "") < (b.name or "")
	end)

	return vim.tbl_map(function(label)
		return {
			text = label.name,
			name = label.name,
			added = false,
			color = label.color,
			description = label.description,
			is_project_label = label.is_project_label,
		}
	end, labels)
end

local function diff_labels(before, after)
	local add = {}
	local remove = {}

	for name in pairs(after) do
		if not before[name] then
			add[#add + 1] = name
		end
	end

	for name in pairs(before) do
		if not after[name] then
			remove[#remove + 1] = name
		end
	end

	table.sort(add)
	table.sort(remove)
	return add, remove
end

local function format_label(item, picker)
	local ret = {}
	local added = item.added
	if picker.list:is_selected(item) then
		added = not added
	end

	ret[#ret + 1] = { added and "󰱒 " or "󰄱 ", "SnacksPickerDelim" }
	ret[#ret + 1] = { " " }

	if item.color and item.color ~= "" then
		vim.list_extend(ret, Snacks.picker.highlight.badge(item.name, item.color))
	else
		ret[#ret + 1] = { item.name }
	end

	if item.description and item.description ~= "" then
		ret[#ret + 1] = { " " }
		ret[#ret + 1] = { item.description, "Comment" }
	end

	if item.is_project_label == false then
		ret[#ret + 1] = {
			col = 0,
			virt_text = { { "[group]  ", "Comment" } },
			virt_text_pos = "right_align",
			hl_mode = "combine",
		}
	end

	return ret
end

local function final_labels(item, label_picker)
	local labels = label_set(item)
	for _, label in ipairs(label_picker:selected({ fallback = true })) do
		labels[label.name] = not label.added or nil
	end
	return labels
end

function M.open(item, ctx)
	if not backend.labels_cached(item.repo) then
		vim.notify("Loading labels for " .. item.repo .. "...", vim.log.levels.INFO)
	end

	backend.list_labels(item.repo, function(labels, err)
		if err then
			vim.notify("gitlab-issues: " .. err, vim.log.levels.ERROR)
			return
		end

		local current = label_set(item)
		local items = label_items(labels)
		for _, label in ipairs(items) do
			label.added = current[label.name] or false
		end

		Snacks.picker({
			title = "Labels for issue #" .. item.iid,
			items = items,
			format = format_label,
			layout = {
				preset = "select",
				layout = { max_width = 80, min_width = 50 },
			},
			main = { current = true },
			focus = "list",
			confirm = function(label_picker)
				local selected = final_labels(item, label_picker)
				local add, remove = diff_labels(current, selected)
				if #add == 0 and #remove == 0 then
					label_picker:close()
					if ctx and ctx.picker and not ctx.picker.closed then
						ctx.picker:focus()
					end
					return
				end

				label_picker:close()
				if ctx and ctx.picker and not ctx.picker.closed then
					ctx.picker:focus()
				end
				vim.notify("Updating labels on #" .. item.iid .. "...", vim.log.levels.INFO)
				backend.update_issue_labels(item, add, remove, function(raw_issue, update_err)
					if update_err then
						vim.notify("gitlab-issues: " .. update_err, vim.log.levels.ERROR)
						return
					end

					if ctx and ctx.picker and ctx.refresh_item and not ctx.picker.closed then
						ctx.refresh_item(ctx.picker, item, raw_issue)
						ctx.picker:focus()
					end
					vim.notify("Updated labels on #" .. item.iid, vim.log.levels.INFO)
				end)
			end,
		})
	end)
end

return M

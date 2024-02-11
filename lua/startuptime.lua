-- (documented in autoload/startuptime.vim)
local extract = function(file, event_types)
  local other_event_type = event_types['other']
  local sourcing_event_type = event_types['sourcing']
  local result = {}
  local occurrences
  for line in io.lines(file) do
    if #line ~= 0 and line:find('^%d') ~= nil then
      if line:find(': --- N?VIM STARTING ---$') ~= nil then
        table.insert(result, {})
        occurrences = {}
      end
      local idx = line:find(':')
      local times = {}
      for s in line:sub(1, idx - 1):gmatch('[^ ]+') do
        table.insert(times, tonumber(s))
      end
      local event = line:sub(idx + 2)
      local type = other_event_type
      if #times == 3 then
        type = sourcing_event_type
      end
      local key = type .. '-' .. event
      if occurrences[key] ~= nil then
        occurrences[key] = occurrences[key] + 1
      else
        occurrences[key] = 1
      end
      -- 'finish' time is reported as 'clock' in --startuptime output.
      local item = {
        event = event,
        occurrence = occurrences[key],
        finish = times[1],
        type = type
      }
      if type == sourcing_event_type then
        item['self+sourced'] = times[2]
        item.self = times[3]
        item.start = item.finish - item['self+sourced']
      else
        item.elapsed = times[2]
        item.start = item.finish - item.elapsed
      end
      table.insert(result[#result], item)
    end
  end
  return result
end

local mean = function(numbers)
  if #numbers == 0 then
    error('vim-startuptime: cannot take mean of empty list')
  end
  local result = 0.0
  for _, number in ipairs(numbers) do
    result = result + number
  end
  result = result / #numbers
  return result
end

-- (documented in autoload/startuptime.vim)
local standard_deviation = function(numbers, ddof, _mean)
  if _mean == nil then
    _mean = mean(numbers)
  end
  local result = 0.0
  for _, number in ipairs(numbers) do
    local diff = _mean - number
    result = result + (diff * diff)
  end
  result = result / (#numbers - ddof)
  result = math.sqrt(result)
  return result
end

-- (documented in autoload/startuptime.vim)
local consolidate = function(items, tfields)
  local lookup = {}
  for _, try in ipairs(items) do
    for _, item in ipairs(try) do
      local key = item.type .. '-' .. item.occurrence .. '-' .. item.event
      if lookup[key] ~= nil then
        for _, tfield in ipairs(tfields) do
          if item[tfield] ~= nil then
            table.insert(lookup[key][tfield], item[tfield])
          end
        end
        lookup[key].tries = lookup[key].tries + 1
      else
        lookup[key] = vim.deepcopy(item)
        for _, tfield in ipairs(tfields) do
          if lookup[key][tfield] ~= nil then
            -- Put item in a list.
            lookup[key][tfield] = {lookup[key][tfield]}
          end
        end
        lookup[key].tries = 1
      end
    end
  end
  local result = {}
  for _, val in pairs(lookup) do
    table.insert(result, val)
  end
  for _, item in ipairs(result) do
    for _, tfield in ipairs(tfields) do
      if item[tfield] ~= nil then
        local _mean = mean(item[tfield])
        -- Use 1 for ddof, for sample standard deviation.
        local std = standard_deviation(item[tfield], 1, _mean)
        item[tfield] = {mean = _mean, std = std}
      end
    end
  end
  table.sort(result, function(i1, i2)
    -- Sort on mean start time, event name, then occurrence.
    if i1.start.mean ~= i2.start.mean then
      return i1.start.mean < i2.start.mean
    elseif i1.event ~= i2.event then
      return i1.event < i2.event
    else
      return i1.occurrence < i2.occurrence
    end
  end)
  return result
end

-- Given extraction results (from startuptime::Extract), drop the entries that
-- correspond to the TUI Neovim process. Neovim #23036, #26790.
-- In Neovim 0.9, the TUI data comes after the main process data. In Neovim
-- 0.10, the startup times are labeled for the different processes
-- (Primary/TUI or Embedded). The main process data can be in either section
-- (for example, it would ordinarily be under "Embedded", but it's under
-- "Primary/TUI" when nvim is called from :!). Here we determine TUI sessions
-- by their lack of an event that occurs for main processes but not the TUI
-- process.
local remove_tui_sessions = function(sessions)
  local result = {}
  for _, session in ipairs(sessions) do
    for _, item in ipairs(session) do
      if item.event == 'opening buffers' then
        table.insert(result, session)
        break
      end
    end
  end
  return result
end

return {
  extract = extract,
  consolidate = consolidate,
  remove_tui_sessions = remove_tui_sessions,
}

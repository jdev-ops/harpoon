local Path = require("plenary.path")

function get_base_datapath()
  local env_var = "NVIM_DATA_PATH"
  local env_val = vim.fn.getenv(env_var)
  if env_val == vim.NIL or env_val == "" then
    return vim.fn.stdpath("data")
   else
    return env_val
  end
end

function get_datapath(section)
  local nvim_id_value = "NVIM_ID"
  local nvim_id = vim.fn.getenv(nvim_id_value)
  if nvim_id == vim.NIL or nvim_id == "" then
    return string.format("%s/%s/", get_base_datapath(), section)
   else
    return string.format("%s/%s_%s/", get_base_datapath(), section, nvim_id)
  end
end

local data_path = get_datapath("harpoon")

local ensured_data_path = false
local function ensure_data_path()
    if ensured_data_path then
        return
    end

    local path = Path:new(data_path)
    if not path:exists() then
        path:mkdir()
    end
    ensured_data_path = true
end

---@param config HarpoonConfig
local filename = function(config)
    return config.settings.key()
end

local function hash(path)
    return vim.fn.sha256(path)
end

---@param config HarpoonConfig
local function fullpath(config)
    local h = hash(filename(config))
    return string.format("%s/%s.json", data_path, h)
end

---@param data any
---@param config HarpoonConfig
local function write_data(data, config)
    Path:new(fullpath(config)):write(vim.json.encode(data), "w")
end

local M = {}

---@param config HarpoonConfig
function M.__dangerously_clear_data(config)
    write_data({}, config)
end

function M.info()
    return {
        data_path = data_path,
    }
end

--- @alias HarpoonRawData {[string]: {[string]: string[]}}

--- @class HarpoonData
--- @field _data HarpoonRawData
--- @field has_error boolean
--- @field config HarpoonConfig
local Data = {}

-- 1. load the data
-- 2. keep track of the lists requested
-- 3. sync save

Data.__index = Data

---@param config HarpoonConfig
---@param provided_path string?
---@return HarpoonRawData
local function read_data(config, provided_path)
    ensure_data_path()

    provided_path = provided_path or fullpath(config)
    local path = Path:new(provided_path)
    local exists = path:exists()

    if not exists then
        write_data({}, config)
    end

    local out_data = path:read()

    if not out_data or out_data == "" then
        write_data({}, config)
        out_data = "{}"
    end

    local data = vim.json.decode(out_data)
    return data
end

---@param config HarpoonConfig
---@return HarpoonData
function Data:new(config)
    local ok, data = pcall(read_data, config)

    return setmetatable({
        _data = data,
        has_error = not ok,
        config = config,
    }, self)
end

---@param key string
---@param name string
---@return string[]
function Data:_get_data(key, name)
    if not self._data[key] then
        self._data[key] = {}
    end

    return self._data[key][name] or {}
end

---@param key string
---@param name string
---@return string[]
function Data:data(key, name)
    if self.has_error then
        error(
            "Harpoon: there was an error reading the data file, cannot read data"
        )
    end

    return self:_get_data(key, name)
end

---@param name string
---@param values string[]
function Data:update(key, name, values)
    if self.has_error then
        error(
            "Harpoon: there was an error reading the data file, cannot update"
        )
    end
    self:_get_data(key, name)
    self._data[key][name] = values
end

function Data:sync()
    if self.has_error then
        return
    end

    local ok, data = pcall(read_data, self.config)
    if not ok then
        error("Harpoon: unable to sync data, error reading data file")
    end

    for k, v in pairs(self._data) do
        data[k] = v
    end

    pcall(write_data, data, self.config)
end

M.Data = Data
M.test = {
    set_fullpath = function(fp)
        fullpath = fp
    end,

    read_data = read_data,
}

return M

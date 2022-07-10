-- Functions for picking fsproj and files


local Path = require 'plenary.path'
local Scandir = require 'plenary.scandir'
local FsProjXml = require 'fsproj-edit.fsproj-xml'

--- Functions to pick fsprojs, files e etc
local M = {}

--- true if path is a git repo
--- @param path string Path of possible repo
--- @return boolean
local function folder_is_repo(path)
  return Path:new(path):joinpath(".git"):exists()
end

--- Find repo for @file_or_folder. If @file_or_folder is null then use cwd.
--- @param file_or_folder string|nil Path to use in the search for a repo. If nil, uses cwd.
--- @return string|nil
local function find_root_folder(--[[ optional ]] file_or_folder)

  -- Use cwd if not path is given
  local path = file_or_folder or vim.loop.cwd()

  local p = Path:new(path)

  -- If path is a directory, check if its repo
  if p:is_dir() then
    if folder_is_repo(path) then
      return path
    end
  end

  -- Check if any of parents is a repo. Get the first found.
  local parents = p:parents()
  for _, parent_path in ipairs(parents) do
    local existe = folder_is_repo(parent_path)
    if existe then
      return parent_path
    end
  end
  return nil

end

--- Find all .fsproj which have the file @src_file_path. Search repo where @src_file_path sits.
--- @param src_file_path string|nil Path to search from. Can be a file or folder. If nil, then uses cwd.
--- @return string[]
local function find_all_fsprojs(--[[ optional ]] src_file_path)

  local repo_path = find_root_folder(src_file_path)
  if not repo_path then
    return {}
  end

  local search = Scandir.scan_dir(repo_path, {
    add_dirs = false,
    respect_gitignore = true,
    search_pattern = "%.fsproj$" })
  return search
end

--- Get all fsproj the has @file_path. Search @file_path for .fsproj.
--- @param file_path string Path of file to find.
--- @return string[]
function M.find_all_fsprojs_with_file(file_path)
  local all_fsprojs = find_all_fsprojs(file_path)
  local results = {}
  for _, fsproj_path in ipairs(all_fsprojs) do
    local fsproj = FsProjXml.load(fsproj_path)
    if fsproj and fsproj:get_file_entry(file_path) then
      table.insert(results, fsproj_path)
    end
  end
  return results
end

--- Select a fsproj on @file_path's repo then call on_pick with selected
--- @param file_path string|nil Caminho de arquivo ou pasta pra procurar por repo. Cwd é usado caso dado nil.
--- @param on_pick fun(string):nil
--- @return nil
function M.pick_fsproj(--[[ optional ]] file_path, on_pick)
  local all_fsprojs = find_all_fsprojs(file_path)
  local _ = vim.ui.select(all_fsprojs,
    { prompt = 'Select fsproj:' },
    on_pick)
  return nil
end

--- Select .fsproj that has @file_path or just return if only one .fsproj has it. Or nil if none has it.
--- Search on repo of @file_path.
--- @param file_path string Code file path to find .fsprojs
--- @param on_pick fun(string):nil Callback with fsproj_path of the found or selected(in case of multiples found).
--- @param on_not_find fun() Callback if none is found.
--- @return nil
function M.pick_fsproj_with_file(file_path, on_pick, --[[optional]] on_not_find)

  local found_fsprojs = M.find_all_fsprojs_with_file(file_path)

  -- If found just 1 then just call back
  -- If theres more than 1 fsproj then select first
  if #found_fsprojs == 1 then
    on_pick(found_fsprojs[1])
    return nil
  elseif #found_fsprojs == 0 and on_not_find then
    on_not_find()
    return nil
  else
    local _ = vim.ui.select(found_fsprojs,
      { prompt = 'Select fsproj:' },
      on_pick)
    return nil
  end
end

--- Select a file form a fsproj. Or error if its not a .fsproj.
--- @param fsproj_path string Path of .fsproj
--- @param on_pick fun(FsProjXmlCodeFileFind):nil Callback with file entry selected.
--- @return nil
function M.pick_file_in_fsproj(fsproj_path, on_pick)
  local fsprojxml = FsProjXml.load(fsproj_path)
  if fsprojxml then
    local file_entries = fsprojxml:file_list()

    local _ = vim.ui.select(file_entries,
      { prompt = 'Select file:',
        format_item = function(item)
          return item.sub_path
        end },
      on_pick)
  end
  return nil
end

return M

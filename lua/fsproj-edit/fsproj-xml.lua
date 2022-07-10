-- fs project edit commands

local SLAXML = require 'fsproj-edit.slaxml.slaxdom' -- also requires slaxml.lua
local Path = require 'plenary.path'
local Job = require 'plenary.job'


--- @class SLAXMLDoc
--- @field root table

--- @class SLAXMLAttr
--- @field name string
--- @field value string

--- @class SLAXMLNode
--- @field kids SLAXMLNode
--- @field el SLAXMLNode
--- @field attr SLAXMLAttr[]

--- @class FsProjXmlFileEntry
--- @field idx number Position of node inside ItemGroup.kids
--- @field sub_path string Relative path inside .fsproj
--- @field node SLAXMLNode slaxml node of file inside ItemGroup.kids


--- Read .fsproj using html-tidy to format because slaxml library fails to parse otherwise.
--- @param proj_path string Path of .fsproj to load
--- @return string .fsproj content
local function read_fsproj_to_text(proj_path)
  if Path:new(proj_path):exists() then
    local ret = Job:new({
      command = require 'fsproj-edit.config'.tidy.program,
      args = { '-xml'; '-indent'; proj_path },
    }):sync()
    return table.concat(ret, '\n')
  else
    error(".fsproj does not exists: " .. proj_path)
  end

end

--- Returns ItemGroupNode node with file entries or nil.
--- @param doc SLAXMLDoc
--- @return SLAXMLNode|nil
local function find_item_group_node(doc)
  if doc.root.name == "Project" then
    for _, v in ipairs(doc.root.el) do
      if v.name == "ItemGroup" then
        -- Procura pra ver se tem <Compile>
        for _, compile in ipairs(v.kids) do
          if compile and compile.name == "Compile" then
            return v
          end
        end
      end
    end
  end
  return nil
end

--- Get list of file entries of ItemGroup node.
--- @param itemgroup_node SLAXMLNode
--- @return FsProjXmlFileEntry[]
local function file_entries(itemgroup_node)
  local results = {}
  if itemgroup_node.kids then
    for idx, v in ipairs(itemgroup_node.kids) do
      local include = v.attr and v.attr[1] and v.attr[1].value
      table.insert(results, { idx = idx; sub_path = include; node = v })
    end
  end
  return results
end

--- Get file entry of file from .fsproj given it's full path. Or nil if its not part of fsproj.
--- @param itemgroup_node SLAXMLNode ItemGroup node with file nodes.
--- @param fsproj_dir string Directory of fsproj. Used to calculate relative paths.
--- @param file_full_path string Full path of the file to get file entry.
--- @return FsProjXmlFileEntry|nil
local function file_entry_with_fpath(itemgroup_node, fsproj_dir, file_full_path)
  if itemgroup_node.kids then
    for idx, v in ipairs(itemgroup_node.kids) do
      if v.attr and v.attr.Include then

        local path = Path:new(v.attr.Include)
        if not (path:is_absolute()) then
          path = Path:new(fsproj_dir):joinpath(path):absolute()
        end
        if path == file_full_path then
          return { idx = idx; sub_path = path; node = v }
        end
      end
    end
  end
  return nil
end

--- Get directory of fsproj_path
--- @param fsproj_path string .fsproj path.
--- @return string Full path of .fsproj's directory.
local function get_proj_dir(fsproj_path)
  -- return Path.new(fsproj_path):parent().filename
  return Path.new(fsproj_path):parent():absolute()
end

--- Insert file into .fsproj's ItemGroup at idx
--- @param item_group SLAXMLNode .fsproj ItemGroup.
--- @param idx number Position to insert.
--- @param proj_dir string Directory of .fsproj.
--- @param file_full_path string File's full path to insert.
--- @return nil
local function insert_new_file(item_group, idx, proj_dir, file_full_path)
  -- FIXME: :make_relative only works if full_path is a subpath of proj_dir.
  local relative_path = Path:new(file_full_path):make_relative(proj_dir)
  local new_el = {
    type = "element",
    name = "Compile",
    attr = {
      { type = "attribute", name = "Include", value = relative_path },
    },
    el = {},
    kids = {},
  }
  table.insert(item_group.kids, idx, new_el)
  return nil
end

--- Move file inside ItemGroup
--- @param from_idx number Position of the one to be moved.
--- @param to_idx number Position to move to.
--- @return nil
local function move_file(item_group, from_idx, to_idx)

  if from_idx < 1 then
    error "Cant move file from before position 1."
  end
  if to_idx > #item_group.kids then
    error "Cant move position of file in fsproj past the count of files."
  end

  -- caso tiver mesma idx, não faz nada
  -- caso for menor ou maior tem que mover itens intermediarios
  if from_idx == to_idx then
    return nil
  else

    -- Como vai remover node antes de inserir em outro local vai alterar lengh
    -- Se elemento for ser reinserido atraz de onde foi removido não precisa fazer nada
    -- Mas se inserir ele afrente onde estava tem que reduzir idx pois ele que estava atraz antes foi removido
    local reinsert_idx
    if to_idx > from_idx then
      reinsert_idx = to_idx - 1
    else
      reinsert_idx = to_idx
    end

    local to_move_node = item_group.kids[from_idx]
    table.remove(item_group.kids, from_idx)
    table.insert(item_group.kids, reinsert_idx, to_move_node)
  end
end

--- Remove file from fsproj
--- @param with_idx number Position of file to be removed.
--- @return nil
local function remove_file(item_group, with_idx)
  table.remove(item_group.kids, with_idx)
end

--- Rename file inside .fsproj
--- @param file_node SLAXMLNode File slaxml node.
--- @param fsproj_dir string .fsproj directory.
--- @param new_full_path string New full path (and not just a name)
--- @return nil
local function rename_file(file_node, fsproj_dir, new_full_path)
  local relative_path = Path:new(new_full_path):make_relative(fsproj_dir)

  if file_node.attr then
    for _, att in ipairs(file_node.attr) do
      if att.name == 'Include' then
        att.value = relative_path
      end
    end
  end
end

--- Run html-tidy to format file at path. slaxml does not have a format function.
--- @param file_path string Path of file to format
--- @return nil
local function tidy_fsproj_file(file_path)
  Job:new({
    command = require 'fsproj-edit.config'.tidy.program,
    args = { '-xml'; '-indent'; '-modify', file_path },
  }):sync()

end

--- @class FsProjXml
--- @field private _fsproj_dir string Directory of loaded .fsproj
--- @field private _fsproj_path string Path of .fsproj loaded
--- @field private _doc SLAXMLDoc slaxml dom of .fsproj loaded
--- @field private _item_group_node SLAXMLNode slaxml node of file's item group
local FsProjXml = {}


-- Create new FsProjXml
function FsProjXml:new(fsproj_path, fsproj_dir, doc, item_group_node)
  local t = setmetatable({}, { __index = FsProjXml })

  t._fsproj_path = fsproj_path
  t._fsproj_dir = fsproj_dir
  t._doc = doc
  t._item_group_node = item_group_node

  return t
end

--- Gets the file entry given a full path of a file or returns nil.
--- @param file_full_path string
--- @return FsProjXmlFileEntry|nil
function FsProjXml:get_file_entry(file_full_path)
  local ret = file_entry_with_fpath(self._item_group_node, self._fsproj_dir, file_full_path)
  return ret or nil
end

--- Insert file in .fsproj dom given it's full path and position to insert.
--- @param idx number Position in the fsproj dom to insert at.
--- @param new_full_path string Full path of file to insert.
--- @return nil
function FsProjXml:insert_new_file(idx, new_full_path)
  insert_new_file(self._item_group_node, idx, self._fsproj_dir, new_full_path)
end

--- Replace path of a file in fsproj dom by new relative computed from the new's full path
--- @param idx number Position in the itemgroup node of the file entry to be renamed
--- @param new_full_path string New full path. Will insert relative computed from this full path.
--- @return nil
function FsProjXml:rename_file(idx, new_full_path)
  local node = self._item_group_node.kids[idx]
  if node then
    rename_file(node, self._fsproj_dir, new_full_path)
  end
end

--- Move file entry from @from_idx to @to_idx
--- @param from_idx number Position of file entry to move.
--- @param to_idx number Position to move into
--- @return nil
function FsProjXml:move_file(from_idx, to_idx)
  move_file(self._item_group_node, from_idx, to_idx)
end

--- Remove from fsproj dom
--- @param del_idx number Position of file entry node to remove inside ItemGroup
--- @return nil
function FsProjXml:remove_file(del_idx)
  remove_file(self._item_group_node, del_idx)
end

--- Get all file entries of fsproj dom
--- @return FsProjXmlFileEntry[]
function FsProjXml:file_list()
  return file_entries(self._item_group_node)
end

--- Save file then format
--- @return nil
function FsProjXml:save()
  local w = io.open(self._fsproj_path, "w")
  local xml_out = SLAXML:xml(self._doc)
  if w then
    w:write(xml_out)
    w:close()

    -- always format because we use html-tidy on read anyway.
    tidy_fsproj_file(self._fsproj_path)
  end
end

--- @class FsProjXmlModule

--- @type FsProjXmlModule
local M = {}

--- Loads .fsproj
--- @param path string Path to .fsproj
--- @return FsProjXml|nil
function M.load(path)
  local fsproj_path = path
  local fsproj_dir = get_proj_dir(path)

  local contents = read_fsproj_to_text(path)
  if contents then
    local doc = SLAXML:dom(contents)

    local item_group_node = find_item_group_node(doc)

    if item_group_node then
      local fsprojxml = FsProjXml:new(fsproj_path, fsproj_dir, doc, item_group_node)
      return fsprojxml
    end
  end
end

return M

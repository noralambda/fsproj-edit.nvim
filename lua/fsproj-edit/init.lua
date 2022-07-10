-- fs project edit commands

local Path = require 'plenary.path'
local FsProjXml = require 'fsproj-edit.fsproj-xml'
local Sel = require 'fsproj-edit.select'


--- Createt new file in the selected fsproj
--- @param ref_path string Full path for a file or folder belonging to the repo.
--- @param idx_delta 0|1 Where to insert. 0 => same index, thus becoming above the previous. 1 => next index(+1), thus bellow
local function create_new_file_with_delta(ref_path, idx_delta)

  Sel.pick_fsproj(ref_path,
    function(fsproj_path)
      Sel.pick_file_in_fsproj(fsproj_path,
        function(file_selected)

          local new_file_idx = file_selected.idx + idx_delta -- below or above(same idx)

          vim.ui.input({ prompt = "New file path(starting from .fsproj)" },
            function(input)
              if input then

                local fsproj_dir = Path:new(fsproj_path):parent()

                local new_file = fsproj_dir:joinpath(input)

                new_file:touch({ parents = true })

                local new_file_fullpath = new_file:absolute()


                local fsxmlproj = FsProjXml.load(fsproj_path)
                if fsxmlproj then

                  fsxmlproj:insert_new_file(new_file_idx, new_file_fullpath)
                  fsxmlproj:save()

                  vim.cmd('edit ' .. new_file_fullpath)
                else
                  error("error loading .fsproj: " .. fsproj_path)
                end
              end
            end)
        end)
    end)
end

--- @class FsProjModule
local M = {}

--- Create file above the selected file in the selected project
--- @return nil
function M.create_file_above_file()
  local buffer_path = vim.fn.expand('%:p', nil, nil)
  create_new_file_with_delta(buffer_path, 0)
end

--- Create file below the selected file in the selected project
--- @return nil
function M.create_file_below_file()
  local buffer_path = vim.fn.expand('%:p', nil, nil)
  create_new_file_with_delta(buffer_path, 1)
end

--- Move file to bellow/above another one selected
--- @param buffer_path string Path of file
--- @param idx_delta 0|1 0 => insert above selected, 1 => insert bellow
local function move_this_file_with_delta(buffer_path, idx_delta)
  Sel.pick_fsproj_with_file(buffer_path,
    function(fsproj_path)
      -- buffer_path: qual idx?
      local fsproj = FsProjXml.load(fsproj_path)
      if not fsproj then
        error("error loading .fsproj: " .. fsproj_path)
        return
      end
      local from = fsproj:get_file_entry(buffer_path)
      if not from then
        error("File not found in any fsproj:" .. buffer_path)
        return nil
      end
      Sel.pick_file_in_fsproj(fsproj_path,
        function(file_entry)
          local from_idx = from.idx
          -- soma 1 ou 0. Com 1 poem abaixo
          local to_idx = file_entry.idx + idx_delta
          fsproj:move_file(from_idx, to_idx)
          fsproj:save()
        end)
    end)

end

--- Move file of current window inside fsproj, above the picked file
--- @return nil
function M.move_this_file_above()
  local buffer_path = vim.fn.expand('%:p', nil, nil)
  move_this_file_with_delta(buffer_path, 0)
  return nil
end

--- Move file of current window inside fsproj, bellow the picked file
--- @return nil
function M.move_this_file_below()
  local buffer_path = vim.fn.expand('%:p', nil, nil)
  move_this_file_with_delta(buffer_path, 1)
  return nil
end

--- Remove file from fsproj it is part of.
--- @return nil
function M.remove_this_file()
  local buffer_path = vim.fn.expand('%:p', nil, nil)
  Sel.pick_fsproj_with_file(buffer_path,
    function(fsproj_path)
      local fsproj = FsProjXml.load(fsproj_path)
      if not fsproj then
        error("error loading .fsproj: " .. fsproj_path)
        return
      end
      local to_del = fsproj:get_file_entry(buffer_path)
      if not to_del then
        vim.schedule(function()
          print("File not found in any fsproj:", buffer_path)
        end)
        return nil
      end
      fsproj:remove_file(to_del.idx)
    end)
end

--- Remove current window file from fsprojs. Delete file from disk. Delete the buffer.
function M.delete_this_file()
  local buffer_path = vim.fn.expand('%:p', nil, nil)
  Sel.pick_fsproj_with_file(buffer_path,
    function(fsproj_path)
      local fsproj = FsProjXml.load(fsproj_path)
      if not fsproj then
        error("error loading .fsproj: " .. fsproj_path)
        return
      end
      local to_del = fsproj:get_file_entry(buffer_path)
      if not to_del then
        vim.schedule(function()
          print("File not found in any fsproj:", buffer_path)
        end)
        return nil
      end
      fsproj:remove_file(to_del.idx)
      Path:new(buffer_path):rm()
      -- Bdelete! option?
      vim.cmd [[bdelete]]
      fsproj:save()
    end)
end

--- Rename file in the buffer, disk and fsprojs it is used in.
--- @return nil
function M.rename_this_file()
  local buffer_path = vim.fn.expand('%:p', nil, nil)
  if not (Path:new(buffer_path):is_file()) then
    error("Cannot rename buffer_path because its not a file: " .. buffer_path)
  end

  vim.ui.input({ prompt = "New full path",
    default = buffer_path },
    function(new_full_path)

      -- moves file
      Path:new(new_full_path):rename({ new_name = new_full_path })
      -- renames buffer
      vim.cmd('file ' .. new_full_path)

      local fsproj_paths = Sel.find_all_fsprojs_with_file(buffer_path)
      for _, fsproj_path in ipairs(fsproj_paths) do
        local fsprojxml = FsProjXml.load(fsproj_path)
        if fsprojxml then
          local fentry = fsprojxml:get_file_entry(buffer_path)
          if fentry then
            fsprojxml:rename_file(fentry.idx, new_full_path)
            fsprojxml:save()
          end
        end
      end
    end)

end

--- Setup fsproj-edit
--- @param opts FsProjEditConfig
--- @return nil
function M.setup(opts)
  if type(opts) == 'table' then
    local config = require 'fsproj-edit.config'
    config.tidy.program = opts.tidy.program or config.tidy.program
  end
end

return M


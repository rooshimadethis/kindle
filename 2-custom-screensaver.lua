-- KOReader Custom Screensaver Patch
-- Path: koreader/patches/2-custom-screensaver.lua
-- Description: Added UI Menu integration under Tools menu

local function main()
    local logger = require("logger")
    local Screen = require("device").screen
    local BlitBuffer = require("ffi/blitbuffer")
    local util = require("util")
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")

    local SETTINGS_FILE = "/mnt/us/koreader/settings/custom_screensaver_patch.lua"
    local config = {
        wallpaper_dir = "/mnt/us/koreader/wallpapers/",
        cover_size_ratio = 0.3,
        shadow_offset = 10,
    }

    local function load_settings()
        local f = loadfile(SETTINGS_FILE)
        if f then
            local ok, saved_config = pcall(f)
            if ok and type(saved_config) == "table" then
                for k, v in pairs(saved_config) do config[k] = v end
            end
        end
    end

    local function save_settings()
        os.execute("mkdir -p /mnt/us/koreader/settings")
        local f = io.open(SETTINGS_FILE, "w")
        if f then
            f:write("return " .. util.tableToString(config))
            f:close()
        end
    end

    local function get_random_wallpaper(path)
        local files = util.getDirFiles(path)
        if not files or #files == 0 then
            os.execute("mkdir -p " .. path)
            return nil 
        end
        local valid_files = {}
        for _, file in ipairs(files) do
            local ext = file:lower():match("%.([^%.]+)$")
            if ext == "png" or ext == "jpg" or ext == "jpeg" then
                table.insert(valid_files, file)
            end
        end
        if #valid_files == 0 then return nil end
        math.randomseed(os.time())
        return path .. valid_files[math.random(#valid_files)]
    end

    local function show_folder_picker()
        local PathChooser = require("ui/widget/pathchooser")
        local lfs = require("libs/libkoreader-lfs")
        local path_chooser = PathChooser:new{
            title = "Select Wallpaper Folder",
            select_directory = true,
            path = config.wallpaper_dir or "/mnt/us/koreader/",
            onConfirm = function(path)
                -- Ensure trailing slash
                if path:sub(-1) ~= "/" then path = path .. "/" end
                config.wallpaper_dir = path
                save_settings()
                
                -- Check for images like the reference plugin
                local has_images = false
                local valid_extensions = { "%.png$", "%.jpg$", "%.jpeg$" }
                pcall(function()
                    for entry in lfs.dir(path) do
                        local lower = entry:lower()
                        for _, ext in ipairs(valid_extensions) do
                            if lower:match(ext) then
                                has_images = true
                                break
                            end
                        end
                        if has_images then break end
                    end
                end)
                
                if has_images then
                    UIManager:show(InfoMessage:new{ text = "Wallpaper folder saved!", timeout = 3 })
                else
                    UIManager:show(InfoMessage:new{ text = "Folder saved, but no images (.png, .jpg) were found!", timeout = 5 })
                end
            end,
        }
        UIManager:show(path_chooser)
    end

    local function hook_screensaver_and_menu()
        local ok, Screensaver = pcall(require, "plugins/screensaver.koplugin/main")
        if not ok or not Screensaver then return false end

        -- 1. Hook the screensaver drawing logic
        Screensaver.drawScreensaver = function(self)
            load_settings()
            local screen_w = Screen:getWidth()
            local screen_h = Screen:getHeight()
            local fb = BlitBuffer:new(screen_w, screen_h, Screen:getBitsPerPixel())
            fb:fill(0xFFFFFFFF, 0, 0, screen_w, screen_h)
            
            local wp_path = get_random_wallpaper(config.wallpaper_dir)
            if wp_path then
                local s, wp = pcall(BlitBuffer.fromFile, BlitBuffer, wp_path)
                if s and wp then fb:blitFrom(wp:scale(screen_w, screen_h), 0, 0) end
            end
            
            local ReaderUI = require("apps/reader/readerui")
            if ReaderUI.instance and ReaderUI.instance.document then
                local cover = require("ui/coverextractor"):getCover(ReaderUI.instance.document.file_path)
                if cover then
                    local target_h = math.floor(screen_h * config.cover_size_ratio)
                    local scaled_cover = cover:scale(math.floor(cover.width * (target_h / cover.height)), target_h)
                    local x = math.floor((screen_w - scaled_cover.width) / 2)
                    local y = math.floor((screen_h - target_h) / 2)
                    fb:fill(0xFF444444, x + config.shadow_offset, y + config.shadow_offset, scaled_cover.width, target_h)
                    fb:blitFrom(scaled_cover, x, y)
                end
            end
            Screen:blitFull(fb)
        end

        -- 2. Hook the menu to add our setting
        -- We hook ReaderUI and FileManager directly to ensure it shows up in Tools
        local function inject_menu_item(menu_items)
            menu_items.custom_wallpaper_folder = {
                text = "Custom Wallpaper Folder",
                sorting_hint = "tools",
                callback = function()
                    show_folder_picker()
                end
            }
        end

        local ReaderUI = require("apps/reader/readerui")
        local orig_onGetTweakMenu = ReaderUI.onGetTweakMenu
        ReaderUI.onGetTweakMenu = function(self, menu_items)
            if orig_onGetTweakMenu then orig_onGetTweakMenu(self, menu_items) end
            inject_menu_item(menu_items)
        end

        local FileManager = require("apps/filemanager/filemanagerui")
        if FileManager then
            local orig_fm_onGetTweakMenu = FileManager.onGetTweakMenu
            FileManager.onGetTweakMenu = function(self, menu_items)
                if orig_fm_onGetTweakMenu then orig_fm_onGetTweakMenu(self, menu_items) end
                inject_menu_item(menu_items)
            end
        end

        -- If Screensaver is already loaded, we might need to force a menu refresh
        -- but usually ReaderUI/FileManager will pick up the change next time the menu is built.
        return true
    end

    load_settings()
    UIManager:scheduleIn(4, hook_screensaver_and_menu)
end

-- Safety Wrapper
local status, err = pcall(main)
if not status then
    local UIManager = require("ui/uimanager")
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:scheduleIn(5, function()
        UIManager:show(InfoMessage:new{ text = "Patch Error: " .. tostring(err), timeout = 10 })
    end)
end

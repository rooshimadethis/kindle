local logger = require("logger")
local Widget = require("ui/widget/widget")
local util = require("util")
local _ = require("gettext")

local CustomScreensaver = Widget:extend{
    name = "custom_screensaver",
}

local config = {
    enabled = true,
    wallpaper_dir = "/mnt/us/screensavers/",
    cover_scale = 0.3,
    shadow_offset = 10,
}

function CustomScreensaver:getReaderUI()
    local ReaderUI = package.loaded["apps/reader/readerui"]
    return ReaderUI and ReaderUI.instance
end

function CustomScreensaver:init()
    logger:info("CustomSS: init()")
    self:loadSettings()
    
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    
    self:hookScreensaver()
end

function CustomScreensaver:loadSettings()
    if G_reader_settings then
        config.enabled = G_reader_settings:readSetting("custom_ss_enabled", true)
        config.wallpaper_dir = G_reader_settings:readSetting("custom_ss_wallpaper_dir", "/mnt/us/screensavers/")
    end
end

function CustomScreensaver:saveSettings()
    if G_reader_settings then
        G_reader_settings:saveSetting("custom_ss_enabled", config.enabled)
        G_reader_settings:saveSetting("custom_ss_wallpaper_dir", config.wallpaper_dir)
    end
end

function CustomScreensaver:getRandomWallpaper()
    local lfs = require("libs/libkoreader-lfs")
    local valid = {}
    
    local ok, err = pcall(function()
        for f in lfs.dir(config.wallpaper_dir) do
            if f ~= "." and f ~= ".." and not f:match("^%._") then
                local full_path = config.wallpaper_dir .. "/" .. f
                local attr = lfs.attributes(full_path)
                if attr and attr.mode == "file" then
                    local lower = f:lower()
                    if lower:match("%.png$") or lower:match("%.jpg$") or lower:match("%.jpeg$") then
                        table.insert(valid, full_path)
                    end
                end
            end
        end
    end)
    
    if #valid > 0 then
        math.randomseed(os.time())
        return valid[math.random(#valid)]
    end
    return nil
end

function CustomScreensaver:generateScreensaverFB()
    local Device = require("device")
    local Screen = Device.screen
    local BlitBuffer = require("ffi/blitbuffer")
    
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local fb = BlitBuffer.new(screen_w, screen_h, Screen.bits_per_pixel)
    
    -- Background
    local wp_path = self:getRandomWallpaper()
    if wp_path then
        local s, wp = pcall(BlitBuffer.fromFile, wp_path)
        if s and wp then 
            fb:blitFrom(wp:scale(screen_w, screen_h), 0, 0) 
        end
    end

    -- Cover
    local ui = self:getReaderUI()
    if ui and ui.document and ui.document.info then
        local cover_fb = ui:getCover()
        if cover_fb then
            local target_w = screen_w * config.cover_scale
            local target_h = (cover_fb.height / cover_fb.width) * target_w
            
            local scaled = cover_fb:scale(target_w, target_h)
            local x = (screen_w - target_w) / 2
            local y = (screen_h - target_h) / 2
            
            fb:blitFrom(scaled, x, y)
        end
    end
    
    return fb
end

function CustomScreensaver:hookScreensaver()
    if self._hooked then return end
    
    local Screensaver = require("ui/screensaver")
    local Device = require("device")
    local UIManager = require("ui/uimanager")
    local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    
    local self_ref = self
    
    -- Use the reference-recommended wrapMethod for clean hooking
    self._screensaver_hook = util.wrapMethod(Screensaver, "show", function(ss_self)
        logger:info("CustomSS: Screensaver triggered")
        
        if not config.enabled then 
            return self_ref._screensaver_hook:raw_call(ss_self) 
        end
        
        -- Close existing widget if present
        if ss_self.screensaver_widget then
            UIManager:close(ss_self.screensaver_widget)
            ss_self.screensaver_widget = nil
        end
        
        Device.screen_saver_mode = true
        local fb = self_ref:generateScreensaverFB()
        
        local ImageViewer = require("ui/widget/imageviewer")
        local image_widget = ImageViewer:new{
            image = fb,
            fullscreen = true,
        }
        
        ss_self.screensaver_widget = ScreenSaverWidget:new {
            widget = image_widget,
            covers_fullscreen = true,
        }
        ss_self.screensaver_widget.modal = true
        ss_self.screensaver_widget.dithered = true
        
        UIManager:show(ss_self.screensaver_widget, "full")
    end)
    
    self._hooked = true
    logger:info("CustomSS: Hook installed using wrapMethod")
end

function CustomScreensaver:showFolderPicker()
    local PathChooser = require("ui/widget/pathchooser")
    local InfoMessage = require("ui/infomessage")
    local UIManager = require("ui/uimanager")
    
    local self_ref = self
    local picker = PathChooser:new{
        title = _("Select Wallpaper Folder"),
        path = config.wallpaper_dir,
        onConfirm = function(path)
            config.wallpaper_dir = path
            self_ref:saveSettings()
            UIManager:show(InfoMessage:new{
                text = _("Wallpaper folder updated!"),
            })
        end,
    }
    UIManager:show(picker)
end

function CustomScreensaver:addToMainMenu(menu_items)
    local self_ref = self
    menu_items.custom_screensaver = {
        text = _("Custom Screensaver Overlay"),
        sub_item_table = {
            {
                text = _("Enabled"),
                checked_func = function() return config.enabled end,
                callback = function()
                    config.enabled = not config.enabled
                    self_ref:saveSettings()
                end,
            },
            {
                text = _("Wallpaper Folder"),
                callback = function()
                    self_ref:showFolderPicker()
                end,
            },
        }
    }
end

return CustomScreensaver

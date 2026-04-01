local logger = require("logger")
local Widget = require("ui/widget/widget")

local WidgetContainer = require("ui/widget/container/widgetcontainer")

local CustomScreensaver = WidgetContainer:extend{
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
    if ReaderUI and ReaderUI.instance then return ReaderUI.instance end
    
    local UIManager = require("ui/uimanager")
    if UIManager.main_ui and UIManager.main_ui.getCover then
        return UIManager.main_ui
    end
    return nil
end

function CustomScreensaver:init()
    logger:info("CustomSS: init()")
    self:loadSettings()
    
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    else
        logger:info("CustomSS: self.ui or self.ui.menu was nil, couldn't register to main menu!")
    end
    
    self:hookScreensaver()
    
    local UIManager = require("ui/uimanager")
    UIManager:scheduleIn(5, function()
        logger:info("CustomSS: RUNNING AUTOMATED FB GENERATION TEST")
        local ok, err = pcall(function()
            self:generateScreensaverFB()
        end)
        if not ok then
            logger:info("CustomSS TEST FATAL ERROR: " .. tostring(err))
        else
            logger:info("CustomSS TEST SUCCESS: FB generated safely!")
        end
    end)
end

function CustomScreensaver:addToMainMenu(menu_items)
    local self_ref = self
    menu_items.custom_screensaver = {
        text = "Custom Screensaver Overlay",
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = "Enabled",
                checked_func = function() return config.enabled end,
                callback = function()
                    config.enabled = not config.enabled
                    self_ref:saveSettings()
                end,
            },
            {
                text = "Wallpaper Folder",
                callback = function()
                    self_ref:showFolderPicker()
                end,
            },
        }
    }
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
    
    logger:info("CustomSS: scanning images")
    local ok, err = pcall(function()
        for f in lfs.dir(config.wallpaper_dir) do
            if f ~= "." and f ~= ".." and not f:match("^%._") then
                local full_path = config.wallpaper_dir .. "/" .. f
                local lower = f:lower()
                if lower:match("%.png$") or lower:match("%.jpg$") or lower:match("%.jpeg$") then
                    table.insert(valid, full_path)
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
    local RenderImage = require("ui/renderimage")
    
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local fb = BlitBuffer.new(screen_w, screen_h, Screen.bits_per_pixel)
    fb:fill(BlitBuffer.COLOR_WHITE)
    
    -- Background
    local wp_path = self:getRandomWallpaper()
    if wp_path then
        logger:info("CustomSS: loading " .. wp_path)
        local ok, wp = pcall(RenderImage.renderImageFile, RenderImage, wp_path, screen_w, screen_h)
        if ok and wp then 
            fb:blitFrom(wp, 0, 0, 0, 0, wp:getWidth(), wp:getHeight()) 
            wp:free() -- Good habit for big buffers
        end
    end

    -- Cover
    local ui = self:getReaderUI()
    if ui and ui.getCover and ui.document then
        logger:info("CustomSS: overlaying cover")
        local cover_fb = ui:getCover()
        if cover_fb then
            local target_w = math.floor(screen_w * config.cover_scale)
            local target_h = math.floor((cover_fb:getHeight() / cover_fb:getWidth()) * target_w)
            
            local ok, scaled = pcall(RenderImage.scaleBlitBuffer, RenderImage, cover_fb, target_w, target_h, false)
            if ok and scaled then
                local x = math.floor((screen_w - scaled:getWidth()) / 2)
                local y = math.floor((screen_h - scaled:getHeight()) / 2)
                
                -- Draw shadow offset using a smaller black BlitBuffer
                local shadow_fb = BlitBuffer.new(scaled:getWidth(), scaled:getHeight(), Screen.bits_per_pixel)
                shadow_fb:fill(BlitBuffer.COLOR_BLACK)
                fb:blitFrom(shadow_fb, x + config.shadow_offset, y + config.shadow_offset, 0, 0, shadow_fb:getWidth(), shadow_fb:getHeight())
                shadow_fb:free()
                
                fb:blitFrom(scaled, x, y, 0, 0, scaled:getWidth(), scaled:getHeight())
                scaled:free()
            end
        end
    end
    
    return fb
end

function CustomScreensaver:hookScreensaver()
    local Screensaver = require("ui/screensaver")
    local Device = require("device")
    local UIManager = require("ui/uimanager")
    local ScreenSaverWidget = require("ui/widget/screensaverwidget")
    local ImageWidget = require("ui/widget/imagewidget")
    
    local self_ref = self
    local orig_show = Screensaver.show
    
    -- Manual Overwrite (Compatible with all versions)
    Screensaver.show = function(ss_self, ...)
        logger:info("CustomSS: Suspending screensaver event")
        
        if not config.enabled then 
            return orig_show(ss_self, ...) 
        end
        
        -- Clean up existing
        if ss_self.screensaver_widget then
            UIManager:close(ss_self.screensaver_widget)
            ss_self.screensaver_widget = nil
        end
        
        Device.screen_saver_mode = true
        local fb = self_ref:generateScreensaverFB()
        
        local image_widget = ImageWidget:new{
            image = fb,
        }
        
        ss_self.screensaver_widget = ScreenSaverWidget:new {
            widget = image_widget,
            covers_fullscreen = true,
        }
        ss_self.screensaver_widget.modal = true
        ss_self.screensaver_widget.dithered = true
        
        UIManager:show(ss_self.screensaver_widget, "full")
    end
    logger:info("CustomSS: Hook installed (direct)")
end

function CustomScreensaver:showFolderPicker()
    local PathChooser = require("ui/widget/pathchooser")
    local InfoMessage = require("ui/widget/infomessage")
    local UIManager = require("ui/uimanager")
    
    local self_ref = self
    local picker = PathChooser:new{
        title = "Select Wallpaper Folder",
        select_directory = true,
        path = config.wallpaper_dir,
        onConfirm = function(path)
            config.wallpaper_dir = path
            self_ref:saveSettings()
            UIManager:show(InfoMessage:new{
                text = "Wallpaper folder updated!",
            })
        end,
    }
    UIManager:show(picker)
end


return CustomScreensaver

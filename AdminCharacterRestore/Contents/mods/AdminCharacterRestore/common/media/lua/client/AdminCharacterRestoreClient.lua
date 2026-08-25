require "AdminCharacterRestoreShared"
require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/AdminPanel/ISAdminPanelUI"

local ACR = AdminCharacterRestore
local FONT_HEIGHT = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HEIGHT = FONT_HEIGHT + 8
local ROW_HEIGHT = FONT_HEIGHT + 16
local PADDING = 6
local adminPanelOriginalCreate
local adminPanelOriginalUpdate
local adminPanelOriginalOption

local function text(key, ...)
    return getText("UI_AdminCharacterRestore_" .. key, ...)
end

local function isLocalAdmin()
    if not isClient() then return false end
    local player = getPlayer()
    if not player then return false end
    local role = player:getRole()
    return player:getAccessLevel() == "admin" or (role and role:getName() == "admin")
end

local function requestList()
    local player = getPlayer()
    if player then
        ACR.debug("Requesting snapshot list")
        sendClientCommand(player, ACR.ID, "ListSnapshots", {})
    end
end

local function requestRelease(player)
    if player then
        ACR.debug("Requesting latest snapshot release")
        sendClientCommand(player, ACR.ID, "ReleaseLatest", {})
    end
end

local function onLocalPlayerDeath(player)
    requestRelease(player)
end

local function onLocalPlayerCreated(playerIndex)
    local player = getSpecificPlayer(playerIndex)
    if player then
        ACR.debug("Requesting latest snapshot refresh")
        sendClientCommand(player, ACR.ID, "RefreshLatest", {})
    end
end

local function drawSnapshotRowContent(list, y, row)
    local color = row.textColor or list.textColor
    if list.selected == row.index then
        list:drawSelection(0, y, list:getWidth(), row.height - 1)
        color = row.selectedTextColor or list.selectedTextColor
    elseif list.mouseoverselected == row.index and list:isMouseOver() and not list:isMouseOverScrollBar() then
        list:drawMouseOverHighlight(0, y, list:getWidth(), row.height - 1)
    end
    list:drawRectBorder(
        0, y, list:getWidth(), row.height, 0.5, list.borderColor.r, list.borderColor.g, list.borderColor.b
    )
    list:drawText(
        row.text, PADDING, y + math.floor((row.height - FONT_HEIGHT) / 2) - 2, color.r, color.g, color.b, color.a,
        list.font
    )
end

local function drawSnapshotRow(list, y, row)
    if not row.height then row.height = list.itemheight end
    if row.height <= 0 then return y + row.height end
    if y + list:getYScroll() + list.itemheight < 0 or y + list:getYScroll() >= list.height then
        return y + row.height
    end
    drawSnapshotRowContent(list, y, row)
    return y + row.height
end

local function createUserSelector(panel)
    panel.users = ISComboBox:new(
        PADDING, PADDING + FONT_HEIGHT + 4, panel.width - PADDING * 2, BUTTON_HEIGHT, panel, panel.onUserChanged
    )
    panel.users:initialise()
    panel.users:instantiate()
    panel.users.noSelectionText = text("User")
    panel:addChild(panel.users)
end

local function createSnapshotList(panel)
    panel.snapshots = ISScrollingListBox:new(PADDING, panel.users:getBottom() + PADDING, panel.width - PADDING * 2, 230)
    panel.snapshots:initialise()
    panel.snapshots:instantiate()
    panel.snapshots.itemheight = ROW_HEIGHT
    panel.snapshots.itemPadY = math.floor((ROW_HEIGHT - FONT_HEIGHT) / 2)
    panel.snapshots.drawBorder = true
    panel.snapshots.doDrawItem = drawSnapshotRow
    panel:addChild(panel.snapshots)
end

local function createActionButton(panel, y, title, callback)
    local button = ISButton:new(PADDING, y, panel.width - PADDING * 2, BUTTON_HEIGHT, title, panel, callback)
    button.yoffset = -1
    button:initialise()
    button:instantiate()
    panel:addChild(button)
    return button
end

local function createActionButtons(panel)
    panel.restore = createActionButton(panel, panel.snapshots:getBottom() + PADDING, text("Restore"), panel.onRestore)
    panel.close = createActionButton(panel, panel.restore:getBottom() + PADDING, text("Close"), panel.onClose)
    panel.close:enableCancelColor()
    panel:setHeight(panel.close:getBottom() + PADDING)
end

local AdminCharacterRestoreUI = ISPanel:derive("AdminCharacterRestoreUI")

function AdminCharacterRestoreUI:createChildren()
    ISPanel.createChildren(self)
    createUserSelector(self)
    createSnapshotList(self)
    createActionButtons(self)
end

function AdminCharacterRestoreUI:prerender()
    ISPanel.prerender(self)
    self:drawText(text("Title"), PADDING, PADDING, 1, 1, 1, 1, UIFont.Small)
end

function AdminCharacterRestoreUI:onUserChanged()
    self:filterSnapshots()
end

function AdminCharacterRestoreUI:filterSnapshots()
    self.snapshots:clear()
    local user = self.users.selected and self.users.selected > 0 and self.users:getOptionData(self.users.selected)
    for _, snapshot in ipairs(self.allSnapshots or {}) do
        if type(snapshot) == "table" and snapshot.username == user then
            local day = snapshot.worldDays and string.format("%.1f", snapshot.worldDays) or "?"
            local label = text("Snapshot", day, tostring(snapshot.snapshotId))
            local restoreName = type(snapshot.restoreName) == "string" and snapshot.restoreName or label
            self.snapshots:addItem(restoreName, snapshot)
        end
    end
end

function AdminCharacterRestoreUI:setData(snapshots, users)
    self.allSnapshots = type(snapshots) == "table" and snapshots or {}
    self.users:clear()
    local userList = type(users) == "table" and users or {}
    for _, username in ipairs(userList) do
        if type(username) == "string" then self.users:addOptionWithData(username, username) end
    end
    if self.users.options[1] then self.users.selected = 1 end
    self:filterSnapshots()
end

function AdminCharacterRestoreUI:onClose()
    self:setVisible(false)
    self:removeFromUIManager()
    AdminCharacterRestoreUI.instance = nil
end

function AdminCharacterRestoreUI:onRestore()
    local selected = self.snapshots.items[self.snapshots.selected]
    if not selected or not selected.item or not selected.item.playerKey then return end
    local player = getPlayer()
    if not player then return end
    ACR.debug("Requesting restore snapshot=" .. tostring(selected.item.snapshotId))
    sendClientCommand(player, ACR.ID, "RestoreSnapshot", {
        playerKey = selected.item.playerKey,
        snapshotId = tostring(selected.item.snapshotId)
    })
end

function AdminCharacterRestoreUI:new(x, y, width, height)
    local panel = ISPanel:new(x, y, width, height)
    setmetatable(panel, self)
    self.__index = self
    panel.moveWithMouse = true
    panel.backgroundColor = { r = 0, g = 0, b = 0, a = 0.85 }
    panel.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    return panel
end

local function openUI()
    if not isLocalAdmin() then return end
    if not AdminCharacterRestoreUI.instance then
        local panel = AdminCharacterRestoreUI:new(120, 120, 560, 1)
        panel:initialise()
        panel:instantiate()
        AdminCharacterRestoreUI.instance = panel
    end
    AdminCharacterRestoreUI.instance:setVisible(true)
    AdminCharacterRestoreUI.instance:addToUIManager()
    requestList()
end

local function logClientRestore(player, snapshot)
    print(
        string.format(
            "[AdminCharacterRestore] action=client_apply target=%s snapshot=%s timestamp=%s",
            tostring(player:getUsername()), tostring(snapshot.id), tostring(ACR.nowMs())
        )
    )
end

local function applySnapshot(snapshot)
    local player = getPlayer()
    if not player or player:isDead() or type(snapshot) ~= "table" then return end
    snapshot = ACR.copyRestorePayload(snapshot)
    if not snapshot then return end

    ACR.debug("Applying snapshot on client id=" .. tostring(snapshot.id))
    ACR.applyRestoreState(player, snapshot)
    logClientRestore(player, snapshot)
end

local function onServerCommand(module, command, args)
    if module ~= ACR.ID or type(command) ~= "string" or (args ~= nil and type(args) ~= "table") then return end
    ACR.debug("Received server command=" .. command)
    if command == "Snapshots" and AdminCharacterRestoreUI.instance then
        AdminCharacterRestoreUI.instance:setData(args and args.snapshots, args and args.users)
        ACR.debug("Updated snapshot list")
    elseif command == "ApplySnapshot" then
        applySnapshot(args and args.snapshot)
    end
end

local function addAdminButton(panel)
    if panel.adminCharacterRestoreBtn or not panel.cancel then return end
    local cancel = panel.cancel
    local button = ISButton:new(
        cancel:getX(), cancel:getY(), cancel:getWidth(), cancel:getHeight(), text("AdminButton"), panel,
        ISAdminPanelUI.onOptionMouseDown
    )
    button.internal = "ADMIN_CHARACTER_RESTORE"
    button:initialise()
    button:instantiate()
    button.borderColor = panel.buttonBorderColor
    button.visible = isLocalAdmin()
    button.enable = button.visible
    panel:addChild(button)
    panel.adminCharacterRestoreBtn = button
    cancel:setY(button:getBottom() + PADDING)
    panel:setHeight(cancel:getBottom() + PADDING + 1)
end

local function createAdminPanel(panel)
    adminPanelOriginalCreate(panel)
    addAdminButton(panel)
end

local function updateAdminPanelButtons(panel)
    adminPanelOriginalUpdate(panel)
    local button = panel.adminCharacterRestoreBtn
    if button then
        button.visible = isLocalAdmin()
        button.enable = button.visible
    end
end

local function onAdminPanelOption(panel, button, x, y)
    if button and button.internal == "ADMIN_CHARACTER_RESTORE" then
        openUI()
        return
    end
    adminPanelOriginalOption(panel, button, x, y)
end

local function installAdminPanelHooks()
    if ISAdminPanelUI._adminCharacterRestoreHooks then return end
    adminPanelOriginalCreate = ISAdminPanelUI.create
    adminPanelOriginalUpdate = ISAdminPanelUI.updateButtons
    adminPanelOriginalOption = ISAdminPanelUI.onOptionMouseDown
    ISAdminPanelUI.create = createAdminPanel
    ISAdminPanelUI.updateButtons = updateAdminPanelButtons
    ISAdminPanelUI.onOptionMouseDown = onAdminPanelOption
    ISAdminPanelUI._adminCharacterRestoreHooks = true
end

installAdminPanelHooks()
Events.OnServerCommand.Add(onServerCommand)
Events.OnPlayerDeath.Add(onLocalPlayerDeath)
Events.OnCreatePlayer.Add(onLocalPlayerCreated)

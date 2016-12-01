require "class"

local Widget = require "widgets/widget"
local TileBG = require "widgets/tilebg"
--local InventorySlot = require "widgets/invslot"
local Image = require "widgets/image"
local ImageButton = require "widgets/imagebutton"
--local Widget = require "widgets/widget"
--local TabGroup = require "widgets/tabgroup"
--local UIAnim = require "widgets/uianim"
--local Text = require "widgets/text"
local FoodSlot = require "widgets/foodslot"--mod
local FoodItem = require "widgets/fooditem"--mod
local Cooking = require "cooking"
local FoodCrafting = Class(Widget, function(self, num_slots)
  Widget._ctor(self, "FoodCrafting")
  self.bg = self:AddChild(TileBG(HUD_ATLAS, "craft_slotbg.tex"))

  --slots
  self.num_slots = num_slots
  self.foodslots = {} -- numeric array holding num_slot foodslots
	self.allfoods = {} -- sorted numeric array of all cooking recipes as fooditems
	self.selfoods = {} -- filtered and sorted numeric array of recipes
	self.shownfoods = {} -- assoc array of foods currently shown in foodslots
	self.focusitem = nil
	self.invIngs = nil -- ingredient values of all the items stored in player inventory
	self.cookerIngs = nil -- ingredient values of items put into the cooker
	self._focused = false -- widget focus status, required for the camera to stop zooming

  self._aliases = { -- cooking ingredient alias mismatch
  	cookedsmallmeat = "smallmeat_cooked",
  	cookedmonstermeat = "monstermeat_cooked",
  	cookedmeat = "meat_cooked"
  }
  --for ingredient, prefab in pairs(self._aliases) do
  --  self._ingredients[ingredient] = self._ingredients[prefab]
  --end

	self.idx = -1
  self._overflow = Input:ControllerAttached() and 3 or 1

  self._open = false
end)

function FoodCrafting:OnAfterLoad(config, owner)
  self.owner = owner
	self.knownfoods = self.owner.components.knownfoods
  self._config = config

  self._ingredients = Cooking.ingredients
  self._tagweights = self:_GetTagWeights()

	local slot_bgs = {}
	for slot_idx=1,self.num_slots do
		table.insert(slot_bgs, self:AddChild(Image(nil)) )
	end
  --- create all the recipes
  local recipes = self.knownfoods:GetKnownFoods()
  for foodname, recipe in pairs(recipes) do
    local fooditem = FoodItem(self.owner, self, recipe)
    table.insert(self.allfoods, fooditem)
    self:AddChild(fooditem)
		fooditem:Hide()
  end

	for slot_idx=1,self.num_slots do
		local foodslot = FoodSlot(self.owner, self, slot_idx, slot_bgs[slot_idx])
		table.insert(self.foodslots, foodslot)
		self:AddChild(foodslot)
	end

	--buttons
  self.downbutton = self:AddChild(ImageButton(HUD_ATLAS, "craft_end_normal.tex", "craft_end_normal_mouseover.tex", "craft_end_normal_disabled.tex"))
  self.upbutton = self:AddChild(ImageButton(HUD_ATLAS, "craft_end_normal.tex", "craft_end_normal_mouseover.tex", "craft_end_normal_disabled.tex"))
  self.downbutton:SetOnClick(function() self:ScrollDown() end)
  self.upbutton:SetOnClick(function() self:ScrollUp() end)

	self:SetOrientation(false) -- only vertical for now

	-- late foreground init is required to overlay it on top of the food icon
	for _,foodslot in ipairs(self.foodslots) do
		foodslot:InitForeground()
	end
end

function FoodCrafting:SetOrientation(horizontal)
    self.horizontal = horizontal
    self.bg.horizontal = horizontal
    if horizontal then
        self.bg.sepim = "craft_sep_h.tex"
    else
        self.bg.sepim = "craft_sep.tex"
    end

		if not self.horizontal then
      if TheInput:ControllerAttached() then
        self:SetPosition(305,0,0)
      else
        self:SetPosition(280,0,0)
      end
	  end

    self.bg:SetNumTiles(self.num_slots)
    local slot_w, slot_h = self.bg:GetSlotSize()
    local w, h = self.bg:GetSize()

    for k,foodslot in ipairs(self.foodslots) do
      local slotpos = self.bg:GetSlotPos(k)
      foodslot:SetPosition( slotpos.x,slotpos.y,slotpos.z )
			foodslot.bgimage:SetPosition( slotpos.x,slotpos.y,slotpos.z )
    end

    local but_w, but_h = self.downbutton:GetSize()

    if horizontal then
        self.downbutton:SetRotation(90)
        self.downbutton:SetPosition(-self.bg.length/2 - but_w/2 + slot_w/2,0,0)
        self.upbutton:SetRotation(-90)
        self.upbutton:SetPosition(self.bg.length/2 + but_w/2 - slot_w/2,0,0)
    else
        self.upbutton:SetPosition(0, - self.bg.length/2 - but_h/2 + slot_h/2,0)
        self.downbutton:SetScale(Vector3(1, -1, 1))
        self.downbutton:SetPosition(0, self.bg.length/2 + but_h/2 - slot_h/2,0)
    end
end

function FoodCrafting:FoodFocus(slot_idx)
	local focusIdx = slot_idx+self.idx
	if focusIdx < 1 or focusIdx > #self.selfoods then
		return false
	end
	local focusItem = self.selfoods[focusIdx]
	if focusItem == self.focusItem then
		return
	end

	if self.focusItem then
		self.focusItem:HidePopup()
	end
	self.focusItem = focusItem

	self.focusItem:ShowPopup(self.cookerIngs)
	self.focusIdx = slot_idx
end

function FoodCrafting:Open(cooker_inst)
	self._cooker = cooker_inst
	self._cookername = cooker_inst.prefab or cooker_inst.inst.prefab
  self._open = true
	self:Enable()
  self:Show()
	--if cooker_inst ~= self.last_cooker or self.sortneeded or self.filterneeded then
  self:SortFoods()
  if TheInput:ControllerAttached() then
    self:FoodFocus(4)
  end
	--end
end

function FoodCrafting:IsOpen()
  return self._open
end

function FoodCrafting:Close(cooker_inst)
  self._open = false
  self._focused = false
  self:Disable()
  self:Hide()
end

-- only this function can be called from the outside
function FoodCrafting:SortFoods()
	if not self._open then return end
	local cooker_ings = self:_GetEntityIngredients(self._cooker) --(self._cooker.components.container)
	local cooker_ingdata = self:_GetIngredientValues(cooker_ings)
	local inv_ings = self:_GetEntityIngredients(self.owner)

	--local cnt=0
	--for _,c_inst in pairs(self.owner.HUD.controls.containers) do
	--	print(c_inst.container.prefab)
	--end
	--local bp = self.owner.components.inventory:GetEquippedItem(EQUIPSLOTS.BODY)
	--if bp and bp.components.container then
	--	bp.components.container:Close()
	--end

	self.cookerIngs = cooker_ingdata
	self.invIngs = nil

	self:_UpdateFoodStats(cooker_ingdata,#cooker_ings,inv_ings)

	table.sort(self.allfoods, function(a,b)
    if a.recipe.correctcooker ~= b.recipe.correctcooker then return a.recipe.correctcooker end
    if a.recipe.readytocook ~= b.recipe.readytocook then return a.recipe.readytocook end
    if b.recipe.name == "wetgoop" then return true elseif a.recipe.name == "wetgoop" then return false end

    --if a.recipe.reqsmatch ~= b.recipe.reqsmatch then return a.recipe.reqsmatch end

    --if a.recipe.unlocked ~= b.recipe.unlocked then return a.recipe.unlocked end
    --if a.recipe.reqsmismatch ~= b.recipe.reqsmismatch then return a.recipe.reqsmismatch end
		if a.recipe.predict ~= b.recipe.predict then return a.recipe.predict > b.recipe.predict end
		if a.recipe.unfulfilled ~= b.recipe.unfulfilled then return a.recipe.unfulfilled < b.recipe.unfulfilled end
    if a.recipe.priority ~= b.recipe.priority then return a.recipe.priority > b.recipe.priority end
		return a.recipe.name > b.recipe.name
  end)

	self:FilterFoods()
end

function FoodCrafting:FilterFoods()
	self.selfoods = {}
	-- define filterfn
	for idx, fooditem in ipairs(self.allfoods) do
		--if not self.filterFn or self.filterFn(fooditem) then
		if fooditem.recipe.correctcooker then
			if not fooditem.recipe.hide then
				table.insert(self.selfoods, fooditem)
			end
		end
		--end
	end

	self:UpdateFoodSlots()
end

function FoodCrafting:UpdateFoodSlots()
	for idx, foodslot in ipairs(self.foodslots) do
		foodslot:ClearFood()
	end

	if self.idx > #self.selfoods - (self.num_slots ) + self._overflow  then
		self.idx = #self.selfoods - (self.num_slots) + self._overflow
	end

  if self.idx < -self._overflow then
    self.idx = -self._overflow
  end

	if self.idx >  -self._overflow then
		self.downbutton:Enable()
	else
		self.downbutton:Disable()
	end

	if #self.selfoods < self.idx + self.num_slots + self._overflow then
		self.upbutton:Disable()
    else
		self.upbutton:Enable()
	end

	for idx=1, self.num_slots do
		local foodidx = idx + self.idx
		if foodidx > 0 and foodidx <= #self.selfoods then
			self.foodslots[idx]:SetFood(self.selfoods[foodidx])
			self.selfoods[foodidx]:SetSlot(self.foodslots[idx])
		end
	end

	if self.focusItem then
		self.focusItem:HidePopup()
		local focusIdx = self.focusIdx + self.idx
		if focusIdx > 0 and focusIdx <= #self.selfoods then
			self.focusItem = self.selfoods[self.focusIdx+self.idx]
			self.focusItem:ShowPopup(self.cookerIngs)
		else
			self.focusItem = nil
		end
	end
end

function FoodCrafting:GetProduct()
  if #self.selfoods == 1 then
    return self.selfoods[1].recipe
  end
  return nil
end

function FoodCrafting:OnControl(control, down)
  if FoodCrafting._base.OnControl(self, control, down) then return true end

  if down then
    if self._focused then
      if control == CONTROL_MAP_ZOOM_IN then
        self:ScrollDown()
        return true
      elseif control == CONTROL_MAP_ZOOM_OUT then
        self:ScrollUp()
        return true
      end
    end
    if control == CONTROL_OPEN_INVENTORY then
      if self._focused then
        self._focused = false
        self.owner.HUD.controls:SetDark(false)
        SetPause(false)

        --self.focusItem:SetScale(Vector3(1.1, 1.1, 1.1))
        self:SetScale(Vector3(0.5, 0.5, 0.5))
      else
        self._focused = true
        self.owner.HUD.controls:SetDark(true)
    		SetPause(true)

        self:SetScale(Vector3(0.6, 0.6, 0.6))
      end
    end
  else -- not down
    if control == CONTROL_CANCEL and self._focused then
      self._focused = false
  	end
  end
end

function FoodCrafting:DoControl(control)
  if control == CONTROL_MOVE_UP then
    self:ScrollDown()
  elseif control == CONTROL_MOVE_DOWN then
    self:ScrollUp()
  end
end

function FoodCrafting:ScrollUp()
  local oldidx = self.idx
  self.idx = self.idx + 1
  self:UpdateFoodSlots()
  if self.idx ~= oldidx then
    self.owner.SoundEmitter:PlaySound("dontstarve/HUD/craft_up")
  end
  --self:UpdateRecipes()
end

function FoodCrafting:ScrollDown()
  local oldidx = self.idx
  self.idx = self.idx - 1
  self:UpdateFoodSlots()
  if self.idx ~= oldidx then
      self.owner.SoundEmitter:PlaySound("dontstarve/HUD/craft_down")
  end
end

function FoodCrafting:OnGainFocus()
  FoodCrafting._base.OnGainFocus(self)
	self._focused = true
end

function FoodCrafting:OnLoseFocus()
  FoodCrafting._base.OnLoseFocus(self)
	self._focused = false
	--[[if self.focusItem then
		self.focusItem:HidePopup()
		self.focusItem = nil
	end]]
end

function FoodCrafting:IsFocused()
	return self._focused
end

function FoodCrafting:_UpdateFoodStats(ingdata, num_ing, inv_ings)
	local cook_priority = -9999
	for idx, fooditem in ipairs(self.allfoods) do
		local recipe = fooditem.recipe
		self.knownfoods:UpdateRecipe(recipe, ingdata)

		recipe.correctcooker = not recipe.specialcooker or recipe.cookername == self._cookername
		if num_ing == 4 and recipe.correctcooker and recipe.reqsmatch then
			recipe.readytocook = true
			if recipe.priority > cook_priority then
				cook_priority = recipe.priority
			end
		end

		recipe.hide = num_ing > 0 and (not recipe.correctcooker or recipe.reqsmismatch)
	end

	if num_ing == 4 then
		-- show only dishes that have a chance of cooking
		for idx, fooditem in ipairs(self.allfoods) do
			local recipe = fooditem.recipe
			if recipe.readytocook then
				 if recipe.priority < cook_priority then
					 recipe.readytocook = false
					 recipe.hide = true
				 end
			else
				recipe.hide = true
			end
		end
	else
		-- predict user input recipe
		for idx, fooditem in ipairs(self.allfoods) do
			local recipe = fooditem.recipe
			recipe.predict = 0
			recipe.unfulfilled = 0
			for _,minset in ipairs(recipe.minlist) do
				local minnames = minset.names
				local mintags = deepcopy(minset.tags)
				local predict = 0
				--for minname, amt in pairs(minnames) do
				for name, name_amt in pairs(ingdata.names) do
					local name_amt_used = 0
					if minnames[name] then
						local name_amt_used = math.min(minnames[name], name_amt)
						predict = predict + 3*name_amt_used+0.5 -- additional 0.5 is required to increase priority for multi ingredient on top of single ingredient
					end

					local name_amt_unused = name_amt - name_amt_used
					if name_amt_unused > 0 then
						for tag, tag_amt in pairs(self._ingredients[name].tags) do
							if mintags[tag] then
								local tag_amt_used = math.min(mintags[tag], tag_amt*name_amt_unused)
								mintags[tag] = mintags[tag] - tag_amt_used
							  predict = predict + tag_amt_used * self._tagweights[tag]+0.5
							end
						end
					end
				end-- loop ingdata.names

				for tag, amt in pairs(mintags) do
					recipe.unfulfilled = recipe.unfulfilled + amt * self._tagweights[tag]
				end
				recipe.predict = math.max(recipe.predict, predict)
			end

		end

		-- calculate what can be cooked
		for idx, fooditem in ipairs(self.allfoods) do
			local recipe = fooditem.recipe
			for k,v in ipairs(ingdata) do

			end
		end
	end

end

function FoodCrafting:_GetIngredientValues(ings)
	local names = {}
	local tags = {}

	for k,v in pairs(ings) do
		local name = self._aliases[v.name] or v.name
		if self._ingredients[name] then
			names[name] = names[name] and names[name] + v.amt or v.amt
			for kk, vv in pairs(self._ingredients[name].tags) do
				tags[kk] = tags[kk] and tags[kk] + vv*v.amt or vv*v.amt
			end
		end
	end

	return {tags = tags, names = names}
end

function FoodCrafting:_GetTagWeights()
	local tagweights = {}
	local tagdata = {}
	for name,ing in pairs(self._ingredients) do
		for tag,amt in pairs(ing.tags) do
			tagdata[tag] = tagdata[tag] and {max=math.max(tagdata[tag].max,amt), cnt=tagdata[tag].cnt+1} or {max=amt,cnt=1}
		end
	end
	for tag,data in pairs(tagdata) do
		tagweights[tag] = math.max(1, 3-math.pow(data.cnt,1/4)) / data.max
	end
	return tagweights
end

function FoodCrafting:_GetEntityIngredients(...)
  local ings = {}
  for _,e in ipairs(arg) do
    local slots = e.GetItems and e:GetItems()
    if slots == nil and e.components and e.components.container then
      slots = e.components.container.slots
    end
    if slots == nil and e.components and e.components.inventory then
      slots = e.components.inventory.itemslots
    end

    if slots == nil then
      slots = {}
    end

  	for k,v in pairs(slots) do
      --print(v and v.prefab or "aw")
			local amt = v.components.stackable and v.components.stackable.stacksize or 1
    	table.insert(ings, {name=v.prefab,amt=amt})
  	end
  end
  return ings
end

function FoodCrafting:_GetContainerIngredients(...)
  local ings = {}

	for _,container in ipairs(arg) do
		local slots = container.slots or container.itemslots or container:GetItems() {}

  	for k,v in pairs(slots) do
      --print(v and v.prefab or "aw")
			local amt = v.components.stackable and v.components.stackable.stacksize or 1
    	table.insert(ings, {name=v.prefab,amt=amt})
  	end
	end
  return ings
end

return FoodCrafting

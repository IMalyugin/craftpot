local function IsDST()
	return TheSim:GetGameID() == "DST"
end

local function IsClientSim()
	return IsDST() and TheNet:GetIsClient()
end

local KnownFoods = Class(function(self)
  self._dtag = 0.5
  self._basiccooker = 'cookpot'
  self._cooker = {} -- openned cooker inst
  self._cookername = self._basiccooker
  self._config = {} -- mod config goes in here onafterload
  self._knownfoods = {} -- enchanced format recipes
  self._loadedfoods = {} -- loaded recipe data
  self._cookerRecipes = {} -- raw format recipes
  self._ingredients = {} -- all known ingredients
  self._alltags = {} -- all known tags
  self._allnames = {} -- all known names

  self._aliases = {
  	cookedsmallmeat = "smallmeat_cooked",
  	cookedmonstermeat = "monstermeat_cooked",
  	cookedmeat = "meat_cooked"
  }

  if IsClientSim() then
    self._filepath = "session/"..(TheNet:GetSessionIdentifier() or "INVALID_SESSION").."/"..(TheNet:GetUserID() or "INVALID_USERID").."_/knownfoods_data"
  	self:OnLoad()
  end
end)

function KnownFoods:OnSave()
  local data = { knownfoods={} }
  for foodname, recipe in pairs(self._loadedfoods) do
    data.knownfoods[foodname] = {times_cooked=recipe.times_cooked}
  end
  for foodname, recipe in pairs(self._knownfoods) do
    data.knownfoods[foodname] = {times_cooked=recipe.times_cooked}
  end
  if IsClientSim() then
    local str = json.encode(data)
    TheSim:SetPersistentString(self._filepath, str, true)
  else
    return data
  end
end

function KnownFoods:OnLoad(data)
  if IsClientSim() then
    -- ClientSim load uses PersistentString data
    TheSim:GetPersistentString(self._filepath, function(success, strdata)
      if success then
        data = json.decode(strdata)
      end
    end)
  else
    -- MasterSim uses OnLoad data
  end

  if data and data.knownfoods then
    self._loadedfoods = data.knownfoods
    local cnt = 0
    for foodname, recipe in pairs(self._loadedfoods) do
      cnt = cnt + 1
    end
    print('Craft Pot ~~~ component loaded '..cnt..' known food recipes')
  else
    print('Craft Pot ~~~ component loaded with no data')
  end
end

function KnownFoods:SetCooker(inst)
  self._cooker = inst
  self._cookername = inst.prefab
end

-- pcall wrapper, returns:
--  1 for success,
--  0 for fail,
-- -1 for compare error,
-- -2 for sum error,
-- -3 for unknown error
function KnownFoods:_ptest(test,names,tags)
  local st,res = pcall(test,'',names,tags)
  return st and (res and 1 or 0) or string.find(res,'compare') and -1 or string.find(res, 'arith') and -2 or -3
end

function KnownFoods:_Composition(list) -- only compose 1 level, because otherwise it will be too complicated for an ordinary person comprehension
  local mix = {} -- initially an AND
  local sets = {} -- specific format {type:'name'/'tag'}_{name/tag}_{amt} = {mix={name/tag={name/tag},amt={amt}}, used={#1,#2,#3}}

	local max_used=0,max_amt=0
  -- first read the recipes in a huge line
  for idx,recipe in ipairs(list) do
    --local branch = {}
    for name, amt in pairs(recipe.names) do
      --table.insert(branch,{name=name,amt=amt})
      local key = 'n_'..name..'_'..amt;
      local used = sets[key] and sets[key].used or {}
      table.insert(used,idx)
      sets[key] = {mix={name=name,amt=amt},used=used}
			if used >= max_used then
				max_used = used
				if amt > max_amt then
					max_amt = amt
				end
    end
    for tag, amt in pairs(recipe.tags) do
      --table.insert(branch,{tag=tag,amt=amt})
      local key = 't_'..tag..'_'..amt;
      local used = sets[key] and sets[key].used or {}
      table.insert(used,idx)
      sets[key] = {mix={tag=tag,amt=amt},used=used}
    end

--    if #list > 1 then
--      table.insert(mix,branch)
--    else
--      mix = branch
--    end
  end
  -- only leave those that are repeating
  local uniques = {}
  for key, data in pairs(sets) do
    --print("~~~ "..key.."="..#data.used.." --- "..#list)
    if #data.used == #list then
      table.insert(mix, data.mix)
    else
      table.insert(uniques, data)
    end
  end

	if #uniques == #list

  --print("~~~"..#uniques.." / "..#mix)
  if #uniques > 0 then
    local alt = {}
    -- let us begin composition
    for _, data in ipairs(uniques) do
      for _, uidx in ipairs(data.used) do
        if not alt[uidx] then
          alt[uidx] = data.mix
				elseif alt[uidx].amt then
					alt[uidx] = {alt[uidx], data.mix}
				else
			    table.insert(alt[uidx], data.mix)
        end
      end
    end
    table.insert(mix, alt)
  end

  return mix
end

function KnownFoods:_Decomposition(minmix)
  local recipe = {minnames={},mintags={}}
  local list = {}
  self:_DecompositionStep(minmix, recipe, list)
  return list
end

function KnownFoods:_DecompositionStep(mix, recipe, list)
  for i=1,#mix do
    local last = table.remove(mix)
    if last.amt then
      if last.name then
        recipe.minnames[last.name] = recipe.minnames[last.name] and recipe.minnames[last.name] + last.amt or last.amt
      elseif last.tag then
        recipe.mintags[last.tag] = recipe.mintags[last.tag] and recipe.mintags[last.tag] + last.amt or last.amt
      end
    else -- uh-oh... recipe split incomming
      for j, branch in ipairs(last) do
        table.insert(mix,branch)
        self:_DecompositionStep(mix, deepcopy(recipe), list)
        table.remove(mix)
      end
      return -- returns will occur inside
    end
  end
  table.insert(list, recipe)
end

function KnownFoods:OnAfterLoad(config)
  self._config = config
  self._Cooking = require "cooking"
  self._ingredients = self._Cooking.ingredients
  self:_FillIngredients()

  self._cookerRecipes = {}
  for cookername,recipes in pairs(self._Cooking.recipes) do
    for foodname,recipe in pairs(recipes) do
      self._cookerRecipes[foodname] = recipe
      self._cookerRecipes[foodname].cookername = cookername
    end
  end

  -- parse recipes from the raw cookbook
  for foodname, recipe in pairs(self._cookerRecipes) do
    local rawRecipe = self:_SmartSearch(recipe.test)
    if rawRecipe and self:MinimizeRecipe(foodname, rawRecipe) then
      self._knownfoods[foodname] = rawRecipe
    end
  end

  -- then apply loaded recipe data to parsed recipes
  for foodname, recipe in pairs(self._loadedfoods) do
    if self._cookerRecipes[foodname] then
      for param, value in pairs(recipe) do
        self._knownfoods[foodname][param] = value
      end
    else
      -- validate recipe existence
      print("Craft Pot ~~~ Could not find global recipe for "..foodname)
    end
  end
end

-- perform iterative search over missing preparedfood list recipes and attempt to find their real recipes
function KnownFoods:_SmartSearch(test)
  --local vtags = {} -- holds tags with possible values {vtags.veggie = {nil, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4}}
  --local vnames = {} -- holds names with possible values {vnames.froglegs = {nil,1,2,3,4}}
  local tags = {}
  local names = {}

  local tags_proxy = {}
  local names_proxy = {}

  local recipe = {tags={},names={}}

  local access_list = {} -- list of {type='names'/'tags', field={field}}

  setmetatable(names_proxy, {__index=function(t,field)
    if self._ingredients[field] then
      table.insert(access_list, {type='names',field=field})
      return names[field]
    else
      print("CraftPot ~ detected invalid ingredient ["..field.."] in one of the recipes.")
      return nil
    end
  end})

  setmetatable(tags_proxy, {__index=function(t,field)
    if self._alltags[field] then
      table.insert(access_list, {type='tags',field=field})
      return tags[field]
    else
      print("CraftPot ~ detected invalid tag ["..field.."] in one of the recipes.")
      return nil
    end
  end})

  local result
  while true do
    access_list = {}
    result = self:_ptest(test,names_proxy,tags_proxy)

    if result == 1 then
      return self:_RawToSimple(names,tags)
    elseif result == -3 or #access_list == 0 then -- test returned unknown error or no access
      print ("Could not find recipe, unknown error"..result)
      return false
    elseif result == -2 then -- test returned arithmetic error
      local found = false
      for idx=#access_list,0,-1 do -- iterate access_list from end to start
        if not recipe[access_list[idx].type] then
          recipe[access_list[idx].type] = 0
          found = true
          break
        end
      end
      if not found then -- could not fix sum error ???
        print ("Could not find recipe, persistent sum error")
        return false
      end
    else -- test returned false or compare error (-1 or 0)
      local access = table.remove(access_list)
      if access.type == 'tags' then
        tags[access.field] = tags[access.field] and tags[access.field] + 0.5 or 0.5
        if tags[access.field] > 4 then -- quit condition, tag over max value
          print ("Could not find recipe, tag over max")
          return false
        end
      elseif access.type == 'names' then
        names[access.field] = names[access.field] and names[access.field] + 1 or 1
        if names[access.field] > 4 then -- quit condition name over max value
          print ("Could not find recipe, name over max")
          return false
        end
      end

    end -- else

  end -- white true

end

function KnownFoods:_RawToSimple(names, tags)
  local recipe = {
    minnames = {},
    mintags = {},
    maxnames = {},
    maxtags = {}
  }

  for name, amount in pairs(names) do
    if amount < 1000 then
      recipe.maxnames[name] = amount
    end
    if amount > 0 then
      recipe.minnames[name] = amount
    end
  end

  for tag, amount in pairs(tags) do
    if amount < 1000 then
      recipe.maxtags[tag] = amount
    end
    if amount > 0 then
      recipe.mintags[tag] = amount
    end
  end

  return recipe
end

function KnownFoods:MinimizeRecipe(foodname,recipe)
  recipe.name = foodname
  recipe.times_cooked = 0
	for k,v in pairs(self._cookerRecipes[foodname]) do
		recipe[k] = v
	end

  -- validate used names and tags
  local names = {}
  local tags = {}
  local test = recipe.test

  for name, amount in pairs(recipe.minnames) do
    names[name] = amount
  end

  for tag, amount in pairs(recipe.mintags) do
    tags[tag] = amount
  end

  if self:_ptest(test, names, tags) ~= 1 then
    print("Craft Pot ~~~ Invalid recipe for "..foodname)
    return false
  end

  local buffer = nil

  -- *************
  -- find minnames
  -- *************
  for name,amount in pairs(names) do
    names[name] = nil
    if self:_ptest(test, names, tags) == 1 then -- _Test[nil] == true, not a required name
      recipe.minnames[name] = nil
    else -- _Test[nil] == false, minname is required
      names[name] = amount - 1

      if self:_ptest(test, names, tags) ~= 1 then -- _Test[amount-1] == false, valid minname
        names[name] = amount
      else -- _Test[amount-1] == true, invalid restriction
        names[name] = 1
        while self:_ptest(test, names, tags) ~= 1 and names[name] <= 4 do
          names[name] = names[name] + 1
        end
        recipe.minnames[name] = names[name]
      end
    end
  end

  -- ************
  -- find mintags
  -- ************
  for tag,amount in pairs(tags) do
    tags[tag] = nil
    if self:_ptest(test, names, tags) == 1 then -- _Test[nil] == true, not a required tag
      recipe.mintags[tag] = nil
    else -- _Test[nil] == false, mintag is required
      tags[tag] = amount - self._dtag

      if self:_ptest(test, names, tags) ~= 1 then -- _Test[amount-1] == false, valid mintag
        tags[tag] = amount
      else -- _Test[amount-1] == true, invalid restriction
        tags[tag] = self._dtag
        while self:_ptest(test, names, tags) ~= 1 and tags[tag] < 1001 do
          tags[tag] = tags[tag] + self._dtag
        end
        recipe.mintags[tag] = tags[tag]
      end
    end
  end

  -- *************
  -- find maxnames
  -- *************
  local maxtest

  for name,_ in pairs(self._allnames) do
    buffer = names[name] or nil

     maxtest = math.max(recipe.minnames[name] and recipe.minnames[name] + 1 or 0, recipe.maxnames[name] and recipe.maxnames[name] + 1 or 0, 1)
     names[name] = maxtest
    if self:_ptest(test, names, tags) == 1 then -- _Test[amount+1] == true, invalid restriction
      names[name] = 4
      if self:_ptest(test, names, tags) == 1 then -- _Test[amount+1] == true and _Test[1000] == true, no restriction needed
        recipe.maxnames[name] = nil
      else -- _Test[amount+1] == true and _Test[1000] == false, restriction is somwhere above
        names[name] = maxtest + 1
        while self:_ptest(test, names, tags) == 1 and names[name] <= 4 do
          names[name] = names[name] + 1
        end
        recipe.maxnames[name] = names[name] - 1
      end
    else -- _Test[amount+1] == false, valid restriction, but maybe we could reduce it
      repeat
        names[name] = names[name] - 1
      until names[name] <= 0 or self:_ptest(test,names,tags) == 1
      recipe.maxnames[name] = names[name]
    end

    names[name] = buffer
  end

  -- ************
  -- find maxtags
  -- ************
  for tag,_ in pairs(self._alltags) do
    buffer = tags[tag] or nil

    maxtest = math.max(recipe.mintags[tag] and recipe.mintags[tag] + self._dtag or 0, recipe.maxtags[tag] and recipe.maxtags[tag] + self._dtag or 0, self._dtag)
    tags[tag] = maxtest
    if self:_ptest(test, names, tags) == 1 then -- _Test[amount+1] == true, invalid restriction
      tags[tag] = 1000
      if self:_ptest(test, names, tags) == 1 then -- _Test[amount+1] == true and _Test[1000] == true, no restriction needed
        recipe.maxtags[tag] = nil
      else -- _Test[amount+1] == true and _Test[1000] == false, restriction is somwhere above
        tags[tag] = maxtest + self._dtag
        while self:_ptest(test, names, tags) == 1 and tags[tag] < 1001 do
          tags[tag] = tags[tag] + self._dtag
        end
        recipe.maxtags[tag] = tags[tag] - self._dtag
      end
    else -- _Test[amount+1] == false, valid restriction, but maybe we could reduce it
      repeat
        tags[tag] = tags[tag] - self._dtag
      until tags[tag] <= 0 or self:_ptest(test,names,tags) == 1
      recipe.maxtags[tag] = tags[tag]
    end

    tags[tag] = buffer
  end


  --------------------------
  -- analog recipe finder --
  --------------------------
  local minnames = recipe.minnames -- these are links to recipe tables,
  local mintags = recipe.mintags   -- any changes to them will be applied to the recipe

  local minnames_list = deepcopy(minnames)
  local mintags_list = deepcopy(mintags)

  recipe.minlist = {{names=minnames_list,tags=mintags_list}}

  -- tracing simple analog
  -- first by trading 1 name for something else
  for minname, amt in pairs(minnames_list) do
    buffer = minnames[minname]
    minnames[minname] = minnames[minname] > 1 and minnames[minname]-1 or nil -- reduce name by 1

 -- try to replace minname it with a new name
    for name,_ in pairs(self._allnames) do
      if name ~= minname then
        minnames[name] = minnames[name] and minnames[name]+1 or 1
        if self:_ptest(test,minnames,mintags) == 1 then
          table.insert(recipe.minlist, {names=deepcopy(minnames),tags=deepcopy(mintags)})
        --  print("Found an analog for "..foodname.." can use "..name.." instead of "..minname)
        end
        minnames[name] = minnames[name] > 1 and minnames[name]-1 or nil
      end
    end

  -- try to replace minname with a new tag
    for tag,_ in pairs(self._alltags) do
      mintags[tag] = mintags[tag] and mintags[tag]+1 or 1
      if self:_ptest(test,minnames,mintags) == 1 then
        table.insert(recipe.minlist, {names=deepcopy(minnames),tags=deepcopy(mintags)})
        --print("Found an analog for "..foodname.." can use "..tag.." instead of "..minname)
      end
      mintags[tag] = mintags[tag] > 1 and mintags[tag]-1 or nil
    end

    minnames[minname] = buffer
  end

  -- then by trading 1 tag for something else
  for mintag, amt in pairs(mintags_list) do
    buffer = mintags[mintag]
    mintags[mintag] = mintags[mintag] > 1 and mintags[mintag]-1 or nil -- reduce mintag by 1

 -- try to replace mintag it with a new name
    for name,_ in pairs(self._allnames) do
      minnames[name] = minnames[name] and minnames[name]+1 or 1
      if self:_ptest(test,minnames,mintags) == 1 then
        table.insert(recipe.minlist, {names=deepcopy(minnames),tags=deepcopy(mintags)})
      --  print("Found an analog for "..foodname.." can use "..name.." instead of "..mintag)
      end
      minnames[name] = minnames[name] > 1 and minnames[name]-1 or nil
    end

  -- try to replace mintag with a new tag
    for tag,_ in pairs(self._alltags) do
      if tag ~= mintag then
        mintags[tag] = mintags[tag] and mintags[tag]+1 or 1
        if self:_ptest(test,minnames,mintags) == 1 then
          table.insert(recipe.minlist, {names=deepcopy(minnames),tags=deepcopy(mintags)})
        --  print("Found an analog for "..foodname.." can use "..tag.." instead of "..mintag)
        end
        mintags[tag] = mintags[tag] > 1 and mintags[tag]-1 or nil
      end
    end

    mintags[mintag] = buffer
  end

	recipe.minmix = self:_Composition(recipe.minlist)
	recipe.maxmix = self:_Composition({{names=recipe.maxnames, tags=recipe.maxtags}})

	for _, minset in ipairs(recipe.minlist) do
		for name, name_amt in pairs(minset.names) do
			for tag, tag_amt in pairs(self._ingredients[name].tags) do
				if minset.tags[tag] then
					minset.tags[tag] = minset.tags[tag] - tag_amt * name_amt
					if minset.tags[tag] <= 0 then
						minset.tags[tag] = nil
					end
				end
			end
		end
	end

  return true
end

function KnownFoods:_Test(foodname, names, tags)
  if self:_ptest(self._cookerRecipes[foodname].test, names, tags) == 1 then -- cooker here has no meaning
    return true
  end
  return false
end

function KnownFoods:_TestMax(foodname, names, tags)
  local recipe = self._knownfoods[foodname]
  if not recipe then
    print('Error in KnownFoods:_TestMax - attempting to test non existant recipe')
    return false
  end

  for name, amt in pairs(names) do

    if recipe.maxnames[name] and amt > recipe.maxnames[name] then
      return false
    end
  end

  for tag, amt in pairs(tags) do
    if recipe.maxtags[tag] and amt > recipe.maxtags[tag] then
      return false
    end
  end

  return true
end

function KnownFoods:_FillIngredients(num_names)
  for name, data in pairs(self._ingredients) do
    self._allnames[name] = num_names and num_names or 4
    for tag, amount in pairs(data.tags) do
      if not self._alltags[tag] then
        self._alltags[tag] = 1000
      end
    end
  end
end

function KnownFoods:IncrementCookCounter(foodname)
  if self._knownfoods[foodname] then
  	local times_cooked = self._knownfoods[foodname].times_cooked or 0
    self._knownfoods[foodname].times_cooked = times_cooked + 1
  end
end

function KnownFoods:GetKnownFoods()
  return self._knownfoods
end

-- function used by foocrafting
function KnownFoods:UpdateRecipe(recipe, ingdata)
	recipe.reqsmatch = false -- all the min requirements are met
	recipe.reqsmismatch = false -- all the max requirements are met
	recipe.readytocook = false -- all ingredients match recipe and cookpot is loaded
	recipe.specialcooker = recipe.cookername ~= self._basiccooker -- does the recipe require special cooker
	recipe.unlocked = not self._config.lock_uncooked or recipe.times_cooked and recipe.times_cooked > 0

	if not self:_TestMax(recipe.name, ingdata.names, ingdata.tags) then
		recipe.reqsmismatch = true
	end
	if self:_Test(recipe.name, ingdata.names, ingdata.tags) then
		recipe.reqsmatch = true
	end
end

return KnownFoods

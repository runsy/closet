closet.container = {}
closet.container.open_containers = {}

function closet.container.get_container_formspec(pos, clicker)
	local gender = player_api.get_gender(clicker)
	local model = player_api.get_gender_model(gender)
	local texture
	if minetest.get_modpath("3d_armor")~=nil then
		local clicker_name = clicker:get_player_name()
		texture = armor.textures[clicker_name].skin..","..
			armor.textures[clicker_name].armor..","..armor.textures[clicker_name].wielditem
	else
		texture = clicker:get_properties().textures[1]
	end
	local spos = pos.x .. "," .. pos.y .. "," .. pos.z

	local formspec =
		"size[8,8.25]" ..
		"model[0,0;5,5;preview_model;"..model..";"..texture..";-10,195]" ..
		"list[current_player;cloths;3,0.25;1,4]" ..
		"list[nodemeta:" .. spos .. ";closet;5,0.25;3,12;]" ..
		"list[current_player;main;0,4.5;8,1;]" ..
		"list[current_player;main;0,5.5;8,3;8]" ..
		default.get_hotbar_bg(0,4.5)
	return formspec
end

-- Allow only "cloth" groups to put/move

minetest.register_allow_player_inventory_action(function(player, action, inventory, inventory_info)
	local stack
	if inventory_info.to_list == "cloths" then
		minetest.chat_send_all("1")
		stack = inventory:get_stack(inventory_info.from_list, inventory_info.from_index)
	elseif action == "put" and inventory_info.listname == "cloths" then
		stack = inventory_info.stack
	else
		return
	end
	if stack then
		local stack_name = stack:get_name()
		local item_group = minetest.get_item_group(stack_name , "cloth")
		if item_group == 0 then --not a cloth
			return 0
		end
		--search for another cloth of the same type
		local cloth_list = player:get_inventory():get_list("cloths")
		for i = 1, #cloth_list do
			local cloth_type = minetest.get_item_group(cloth_list[i]:get_name(), "cloth")
			if cloth_type == item_group then
				return 0
			end
		end
		return 1
	end
	return 0
end)

function closet.container.container_lid_close(pn)
	local container_open_info = closet.container.open_containers[pn]
	local pos = container_open_info.pos
	local sound = container_open_info.sound
	local swap = container_open_info.swap

	closet.container.open_containers[pn] = nil
	for k, v in pairs(closet.container.open_containers) do
		if v.pos.x == pos.x and v.pos.y == pos.y and v.pos.z == pos.z then
			return true
		end
	end

	local node = minetest.get_node(pos)
	minetest.after(0.2, minetest.swap_node, pos, { name = "closet:" .. swap,
			param2 = node.param2 })
	minetest.sound_play(sound, {gain = 0.3, pos = pos, max_hear_distance = 10})
end

minetest.register_on_leaveplayer(function(player)
	local pn = player:get_player_name()
	if closet.container.open_containers[pn] then
		closet.container.container_lid_close(pn)
	end
end)

function closet.container.container_lid_obstructed(pos, direction)
	if direction == "above" then
		pos = {x = pos.x, y = pos.y + 1, z = pos.z}
	end
	local def = minetest.registered_nodes[minetest.get_node(pos).name]
	-- allow ladders, signs, wallmounted things and torches to not obstruct
	if def and
			(def.drawtype == "airlike" or
			def.drawtype == "signlike" or
			def.drawtype == "torchlike" or
			(def.drawtype == "nodebox" and def.paramtype2 == "wallmounted")) then
		return false
	end
	return true
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "closet:container" then
		return
	end
	if not player or not fields.quit then
		return
	end
	local pn = player:get_player_name()

	if not closet.container.open_containers[pn] then
		return
	end

	local cloth = player_api.compose_cloth(player)
	local gender = player:get_meta():get_string("gender")
	player_api.registered_models[player_api.get_gender_model(gender)].textures[1] = cloth
	local player_name = player:get_player_name()
	armor.textures[player_name].skin = cloth
	player_api.set_textures(player, player_api.registered_models[player_api.get_gender_model(gender)].textures)

	closet.container.container_lid_close(pn)
	return true
end)

function closet.register_container(name, d)
	local def = table.copy(d)
	def.drawtype = 'mesh'
	def.paramtype = "light"
	def.paramtype2 = "facedir"
	def.is_ground_content = false

	def.on_construct = function(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("infotext", d.description)
		local inv = meta:get_inventory()
		inv:set_size("closet", 12*1)
	end
	def.can_dig = function(pos,player)
		local meta = minetest.get_meta(pos);
		local inv = meta:get_inventory()
		return inv:is_empty("closet")
	end
	def.on_rightclick = function(pos, node, clicker)
		minetest.sound_play(def.sound_open, {gain = 0.3, pos = pos, max_hear_distance = 10})
		if not closet.container.container_lid_obstructed(pos, "above") then
			minetest.swap_node(pos, {
					name = "closet:" .. name .. "_open",
					param2 = node.param2 })
		end
		minetest.after(0.2, minetest.show_formspec,
				clicker:get_player_name(),
				"closet:container", closet.container.get_container_formspec(pos, clicker))
		closet.container.open_containers[clicker:get_player_name()] = { pos = pos, sound = def.sound_close, swap = name }
	end
	def.on_blast = function(pos)
		local drops = {}
		default.get_inventory_drops(pos, "closet", drops)
		drops[#drops+1] = "closet:" .. name
		minetest.remove_node(pos)
		return drops
	end

	local def_opened = table.copy(def)
	local def_closed = table.copy(def)

	def_opened.mesh = "closet_open.obj"
	def_opened.tiles = {"closet_closet_open.png",}
	def_opened.drop = "closet:" .. name
	def_opened.groups.not_in_creative_inventory = 1
	def_opened.can_dig = function()
		return false
	end
	def_opened.on_blast = function() end

	minetest.register_node("closet:" .. name, def_closed)
	minetest.register_node("closet:" .. name .. "_open", def_opened)

end
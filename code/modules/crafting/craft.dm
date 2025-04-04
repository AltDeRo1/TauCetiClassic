/datum/personal_crafting
	var/busy
	var/datum/action/innate/crafting/button
	var/display_craftable_only = FALSE
	var/display_compact = TRUE

	var/static/recipe_image_cache = list() // used for storing the icons of results

/*	This is what procs do:
	get_environment - gets a list of things accessable for crafting by user
	get_surroundings - takes a list of things and makes a list of key-types to values-amounts of said type in the list
	check_contents - takes a recipe and a key-type list and checks if said recipe can be done with available stuff
	check_tools - takes recipe, a key-type list, and a user and checks if there are enough tools to do the stuff, checks bugs one level deep
	construct_item - takes a recipe and a user, call all the checking procs, calls do_after, checks all the things again, calls del_reqs, creates result, calls CheckParts of said result with argument being list returned by deel_reqs
	del_reqs - takes recipe and a user, loops over the recipes reqs var and tries to find everything in the list make by get_environment and delete it/add to parts list, then returns the said list
*/

/datum/personal_crafting/proc/check_contents(datum/crafting_recipe/R, list/contents)
	for(var/A in R.reqs)
		var/needed_amount = R.reqs[A]
		for(var/B in contents)
			if(!ispath(B, A) || R.blacklist.Find(B))
				continue

			needed_amount -= contents[B]
			if(needed_amount <= 0)
				break

		if(needed_amount > 0)
			return FALSE

	for(var/A in R.chem_catalysts)
		if(contents[A] < R.chem_catalysts[A])
			return 0
	return 1

/datum/personal_crafting/proc/get_environment(mob/user, list/blacklist=null)
	. = list()
	for(var/obj/item/I in list(user.l_hand, user.r_hand))
		. += I
	if(!isturf(user.loc))
		return
	var/list/L = block(get_step(user, SOUTHWEST), get_step(user, NORTHEAST))
	for(var/A in L)
		var/turf/T = A
		if(T.Adjacent(user))
			for(var/B in T)
				var/atom/movable/AM = B
				if(AM.flags_2 & HOLOGRAM_2 || (blacklist && (AM.type in blacklist)))
					continue
				. += AM

/datum/personal_crafting/proc/get_surroundings(mob/user, list/blacklist=null)
	. = list()
	for(var/obj/I in get_environment(user, blacklist))
		if(I.flags_2 & HOLOGRAM_2)
			continue
		if(istype(I, /obj/item/stack))
			var/obj/item/stack/S = I
			.[I.type] += S.amount
		else
			if(I.flags & OPENCONTAINER)
				for(var/datum/reagent/A in I.reagents.reagent_list)
					.[A.type] += A.volume
			.[I.type] += 1

/datum/personal_crafting/proc/check_tools(mob/user, datum/crafting_recipe/R, list/contents)
	if(!R.tools.len)
		return 1
	var/list/possible_tools = list()
	for(var/obj/item/I in user.contents)
		if(istype(I, /obj/item/weapon/storage))
			for(var/obj/item/SI in I.contents)
				possible_tools += SI.type
		possible_tools += I.type
	possible_tools += contents

	main_loop:
		for(var/A in R.tools)
			for(var/I in possible_tools)
				if(ispath(I,A))
					continue main_loop
			return 0
	return 1

/datum/personal_crafting/proc/construct_item(mob/user, datum/crafting_recipe/R, overrided_time = null)
	var/list/contents = get_surroundings(user, R.blacklist)
	if(check_contents(R, contents))
		if(check_tools(user, R, contents))
			var/required_time = overrided_time
			if(!required_time)
				required_time = R.time
			if(R.required_proficiency)
				required_time = apply_skill_bonus(user, R.time, R.required_proficiency, multiplier = -0.4)
			if(do_after(user, required_time, target = user))
				contents = get_surroundings(user, R.blacklist)
				if(!check_contents(R, contents))
					return ", missing component."
				if(!check_tools(user, R, contents))
					return ", missing tool."
				var/list/parts = del_reqs(R, user)
				var/atom/movable/I = new R.result (get_turf(user.loc))
				I.CheckParts(parts, R)
				I.pixel_x = rand(-10, 10)
				I.pixel_y = rand(-10, 10)
				return 0
			return "."
		return ", missing tool."
	return ", missing component."


/*Del reqs works like this:

	Loop over reqs var of the recipe
	Set var amt to the value current cycle req is pointing to, its amount of type we need to delete
	Get var/surroundings list of things accessable to crafting by get_environment()
	Check the type of the current cycle req
		If its reagent then do a while loop, inside it try to locate() reagent containers, inside such containers try to locate needed reagent, if there isnt remove thing from surroundings
			If there is enough reagent in the search result then delete the needed amount, create the same type of reagent with the same data var and put it into deletion list
			If there isnt enough take all of that reagent from the container, put into deletion list, substract the amt var by the volume of reagent, remove the container from surroundings list and keep searching
			While doing above stuff check deletion list if it already has such reagnet, if yes merge instead of adding second one
		If its stack check if it has enough amount
			If yes create new stack with the needed amount and put in into deletion list, substract taken amount from the stack
			If no put all of the stack in the deletion list, substract its amount from amt and keep searching
			While doing above stuff check deletion list if it already has such stack type, if yes try to merge them instead of adding new one
		If its anything else just locate() in in the list in a while loop, each find --s the amt var and puts the found stuff in deletion loop

	Then do a loop over parts var of the recipe
		Do similar stuff to what we have done above, but now in deletion list, until the parts conditions are satisfied keep taking from the deletion list and putting it into parts list for return

	After its done loop over deletion list and delete all the shit that wasnt taken by parts loop

	del_reqs return the list of parts resulting object will recieve as argument of CheckParts proc, on the atom level it will add them all to the contents, on all other levels it calls ..() and does whatever is needed afterwards but from contents list already
*/

/datum/personal_crafting/proc/del_reqs(datum/crafting_recipe/R, mob/user)
	var/list/surroundings
	var/list/Deletion = list()
	. = list()
	var/data
	var/amt
	main_loop:
		for(var/A in R.reqs)
			amt = R.reqs[A]
			surroundings = get_environment(user)
			surroundings -= Deletion
			if(ispath(A, /datum/reagent))
				var/datum/reagent/RG = new A
				var/datum/reagent/RGNT
				while(amt > 0)
					var/obj/RC = locate() in surroundings
					if(RC && RC.reagents)
						RG = RC.reagents.get_reagent(A)
						if(RG)
							if(!locate(RG.type) in Deletion)
								Deletion += new RG.type()
							if(RG.volume > amt)
								RG.volume -= amt
								data = RG.data
								RC.reagents.conditional_update(RC)
								RG = locate(RG.type) in Deletion
								RG.volume = amt
								RG.data += data
								continue main_loop
							else
								surroundings -= RC
								amt -= RG.volume
								RC.reagents.reagent_list -= RG
								RC.reagents.conditional_update(RC)
								RGNT = locate(RG.type) in Deletion
								RGNT.volume += RG.volume
								RGNT.data += RG.data
								qdel(RG)
						else
							surroundings -= RC
					else
						surroundings -= RC
			else if(ispath(A, /obj/item/stack))
				var/obj/item/stack/S
				var/obj/item/stack/SD
				while(amt > 0)
					S = locate(A) in surroundings
					if(S.amount >= amt)
						if(!locate(S.type) in Deletion)
							SD = new S.type()
							Deletion += SD
						S.use(amt)
						SD = locate(S.type) in Deletion
						SD.amount += amt
						continue main_loop
					else
						amt -= S.amount
						if(!locate(S.type) in Deletion)
							Deletion += S
						else
							data = S.amount
							S = locate(S.type) in Deletion
							S.add(data)
						surroundings -= S
			else
				var/atom/movable/I
				while(amt > 0)
					I = locate(A) in surroundings
					Deletion += I
					surroundings -= I
					amt--
	var/list/partlist = list(R.parts.len)
	for(var/M in R.parts)
		partlist[M] = R.parts[M]
	for(var/A in R.parts)
		if(istype(A, /datum/reagent))
			var/datum/reagent/RG = locate(A) in Deletion
			if(RG.volume > partlist[A])
				RG.volume = partlist[A]
			. += RG
			Deletion -= RG
			continue
		else if(istype(A, /obj/item/stack))
			var/obj/item/stack/ST = locate(A) in Deletion
			if(ST.amount > partlist[A])
				ST.amount = partlist[A]
			var/obj/O = A
			ST.color = O.color
			. += ST
			Deletion -= ST
			continue
		else
			while(partlist[A] > 0)
				var/atom/movable/AM = locate(A) in Deletion
				if(isobj(A))
					var/obj/O = A
					AM.color = O.color
				. += AM
				Deletion -= AM
				partlist[A] -= 1
	while(Deletion.len)
		var/DL = Deletion[Deletion.len]
		Deletion.Cut(Deletion.len)
		qdel(DL)

/datum/personal_crafting/proc/ui_interact(mob/user)
	if(user.incapacitated() || user.lying)
		return

	var/dat
	if(busy)
		dat += "Crafting..."
	else
		if(config.craft_recipes_visibility) // no point in this button, if this disabled on server.
			dat += "<A href='byond://?src=\ref[src];action=toggle_recipes'>[!display_craftable_only ? "Showing All Recipes" : "Showing Craftable Recipes"]</A>"
		dat += "<A href='byond://?src=\ref[src];action=toggle_compact'>[display_compact ? "Compact" : "Detailed"]</A>"
		dat += "<BR>"
		dat += "<div class='Section'>"

		var/list/surroundings = get_surroundings(user)
		var/found_any_recipe = FALSE

		for(var/rec in crafting_recipes)
			var/datum/crafting_recipe/R = rec
			var/can_craft = check_contents(R, surroundings)

			if(!can_craft && (display_craftable_only || !config.craft_recipes_visibility))
				continue

			found_any_recipe = TRUE
			dat += "<hr>"
			var/list/recipe_data = build_recipe_data(R)
			if(display_compact)
				dat += "<div class='connect_description'>"
				if(can_craft)
					dat += "<img src='data:image/jpeg;base64,[GetIconForResult(R)]'/>"
					dat += "[recipe_data["name"]]:&nbsp&nbsp<A href='byond://?src=\ref[src];action=make;recipe=[recipe_data["ref"]]'>Craft"
				else
					dat += "<img src='data:image/jpeg;base64,[GetIconForResult(R)]'/>"
					dat += "[recipe_data["name"]]:&nbsp&nbsp<span class='disabled'>Craft"
				dat += "<span class='description'>"
				dat += "REQUIREMENTS: [recipe_data["req_text"]]"
				if(recipe_data["catalyst_text"])
					dat += "<br>CATALYSTS: [recipe_data["catalyst_text"]]"
				if(recipe_data["tool_text"])
					dat += "<br>TOOLS: [recipe_data["tool_text"]]"
				dat += "</span>"
				if(can_craft)
					dat += "</A>"
				else
					dat += "</span>"
				dat += "</div>"
				dat += "<hr>"
			else
				if(can_craft)
					dat += "<img src='data:image/jpeg;base64,[GetIconForResult(R)]'/>"
					dat += "[recipe_data["name"]]:&nbsp&nbsp<A href='byond://?src=\ref[src];action=make;recipe=[recipe_data["ref"]]'>Craft</A>"
				else
					dat += "<img src='data:image/jpeg;base64,[GetIconForResult(R)]'/>"
					dat += "[recipe_data["name"]]:&nbsp&nbsp<span class='disabled'>Craft</span>"
				dat += "<br>REQUIREMENTS: [recipe_data["req_text"]]"
				if(recipe_data["catalyst_text"])
					dat += "<br>CATALYSTS: [recipe_data["catalyst_text"]]"
				if(recipe_data["tool_text"])
					dat += "<br>TOOLS: [recipe_data["tool_text"]]"
				dat += "<hr>"

		if(!found_any_recipe)
			dat += "Nothing to craft."

		dat += "</div>"

	var/datum/browser/popup = new(user, "crafting", "Crafting Menu", 500, 600)
	popup.set_content(dat)
	popup.open()

/datum/personal_crafting/Topic(href, href_list)
	..()

	if(usr.incapacitated())
		return

	if(usr.lying)
		to_chat(usr, "<span class='notice'>You can't interact with this while lying.</span>")
		return

	switch(href_list["action"])
		if("make")
			if(usr.is_busy())
				return
			var/datum/crafting_recipe/TR = locate(href_list["recipe"])
			busy = TRUE
			ui_interact(usr) //explicit call to show the busy display
			var/fail_msg = construct_item(usr, TR)
			if(!fail_msg)
				to_chat(usr, "<span class='notice'>[TR.name] constructed.</span>")
			else
				to_chat(usr, "<span class='warning'>Construction failed[fail_msg]</span>")
			busy = FALSE
		if("toggle_recipes")
			display_craftable_only = !display_craftable_only
		if("toggle_compact")
			display_compact = !display_compact

	ui_interact(usr)

/datum/personal_crafting/proc/build_recipe_data(datum/crafting_recipe/R)
	var/list/data = list()
	data["name"] = R.name
	data["ref"] = "\ref[R]"
	var/req_text = ""
	var/tool_text = ""
	var/catalyst_text = ""

	for(var/a in R.reqs)
		//We just need the name, so cheat-typecast to /atom for speed (even tho Reagents are /datum they DO have a "name" var)
		//Also these are typepaths so sadly we can't just do "[a]"
		var/atom/A = a
		req_text += " [R.reqs[A]] [initial(A.name)],"
	req_text = replacetext(req_text,",","",-1)
	data["req_text"] = req_text

	for(var/a in R.chem_catalysts)
		var/atom/A = a //cheat-typecast
		catalyst_text += " [R.chem_catalysts[A]] [initial(A.name)],"
	catalyst_text = replacetext(catalyst_text,",","",-1)
	data["catalyst_text"] = catalyst_text

	for(var/a in R.tools)
		var/atom/A = a //cheat-typecast
		tool_text += " [R.tools[A]] [initial(A.name)],"
	tool_text = replacetext(tool_text,",","",-1)
	data["tool_text"] = tool_text

	return data

/datum/personal_crafting/proc/GetIconForResult(datum/crafting_recipe/R)
	if(recipe_image_cache[R.result])
		return recipe_image_cache[R.result]
	var/obj/stored_result = new R.result
	recipe_image_cache[R.result] = bicon_raw(icon(stored_result.icon, stored_result.icon_state))
	qdel(stored_result)
	return recipe_image_cache[R.result]

/datum/personal_crafting/proc/craft_until_cant(datum/crafting_recipe/recipe_to_use, mob/chef, turf/craft_location, craft_time)
	if(!craft_time)
		craft_time = recipe_to_use.time
	while(TRUE)
		// attempt_craft_loop sleeps, so this won't freeze the server while we craft
		if(!attempt_craft_loop(recipe_to_use, chef, craft_location, craft_time))
			break
		craft_time = max(5, craft_time * 0.75) // speed up the more you craft in a batch

/// Attempts a crafting loop. Returns true if it succeeds, false otherwise
/datum/personal_crafting/proc/attempt_craft_loop(datum/crafting_recipe/recipe_to_use, mob/chef, turf/craft_location, craft_time)
	var/list/surroundings = get_surroundings(chef)
	if(!check_contents(recipe_to_use, surroundings))
		to_chat(chef, "failed to craft, missing ingredients!")
		return FALSE

	var/atom/movable/result = construct_item(chef, recipe_to_use, craft_time)
	if(istext(result))
		to_chat(chef, "failed to craft[result]")
		return FALSE
	to_chat(chef, "[chef] crafted [recipe_to_use]")
	recipe_to_use.on_craft_completion(chef, result)
	return TRUE

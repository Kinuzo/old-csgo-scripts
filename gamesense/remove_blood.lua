local sangue_checkbox = ui.new_checkbox("MISC", "Miscellaneous", "Remove blood") 

client.set_event_callback("setup_command", function(e)
    if ui.get(sangue_checkbox) then
		client.exec("r_cleardecals")
	end
end)

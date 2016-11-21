name = "Craft Pot"
author = "IvanX"
version = "0.9"
description = "Don't you think cooking and crafting are lot alike?"

priority = -1337

forumthread = ""
api_version = 6
api_version_dst = 10

dont_starve_compatible = true
reign_of_giants_compatible = true
shipwrecked_compatible = true
dst_compatible = true

icon_atlas = "modicon.xml"
icon = "modicon.tex"

--These let clients know if they need to get the mod from the Steam Workshop to join the game
all_clients_require_mod = false

--This determines whether it causes a server to be marked as modded (and shows in the mod list)
client_only_mod = true

--This lets people search for servers with this mod by these tags
server_filter_tags = {}

configuration_options =
{
  {
    name = "lock_uncooked",
    label = "Lock uncooked",
    options =
    {
        {description = "Off", data = false},
        {description = "On", data = true},
    },
    default = false
  }
}

publisher connects the MT5 "Send public" button to the project's own ai/ and session/ packages (unchanged).

Flow: button -> screenshot (panel hidden) -> HeySolo\TelegramBridge\Public\*.evt -> watcher -> ai.motivation.make (caption) -> preview with Send / Cancel buttons in the bot's "Public" topic -> after Send (admins only): session.manager.send to every destination.

The "Public" topic is one of the bot's normal group topics (Admin › Reporting group): every Send public preview and result goes there. If it is missing the bot recreates it; if no group is set, the admins' private chats are used.

Setup in the bot (admin, private chat):
/pub_login            add a Telegram session (or /pub_session <name> to pick an existing one)
Admin › Public Poster: pick the AI preset, set the key, choose the model from the list; each destination has its own caption language
/pub_add <target>     @channel, t.me/name, t.me/c/id/topic, -100id[:topic]
/pub_test             preview a caption
Then press "Send public" on the chart panel.

If the MT5 Common\Files folder is not the default one, set bridge_root in data/public_poster.json.

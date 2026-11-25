extends RefCounted
## Checking GitHub for a newer release of the game.

const API := "https://api.github.com/repos/Martin-Hourigan/Warband/releases/latest"
const APK := "user://update.apk"  ## where a downloaded update waits for the installer


## This build's version, e.g. "0.2" (from the project settings).
static func current() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0"))


## Whether release tag a (e.g. "v0.3") is newer than version b (e.g. "0.2").
static func newer(a: String, b: String) -> bool:
	var x := a.trim_prefix("v").split(".")
	var y := b.trim_prefix("v").split(".")
	for i in maxi(x.size(), y.size()):
		var p := int(x[i]) if i < x.size() else 0
		var q := int(y[i]) if i < y.size() else 0
		if p != q:
			return p > q
	return false


## From the GitHub latest-release reply: {tag, url, page}: the APK link and the
## release page. Empty if the reply isn't usable or has no APK.
static func read_release(body: String) -> Dictionary:
	var d: Variant = JSON.parse_string(body)
	if typeof(d) != TYPE_DICTIONARY or not d.has("tag_name"):
		return {}
	for a in d.get("assets", []):
		if str(a.get("name", "")).ends_with(".apk"):
			return {"tag": d.tag_name, "url": a.browser_download_url, "page": d.get("html_url", "")}
	return {}


## Hand a downloaded APK to Android's installer, which asks "update this app?".
## (Godot opens local files through its file provider, so the system can read it.)
static func install() -> void:
	OS.shell_open(ProjectSettings.globalize_path(APK))

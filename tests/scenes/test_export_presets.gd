## Tests for the release builds' configuration: Windows and Linux presets that embed the game
## data, leave tests and tooling out and write under the git-ignored export/ folder, and the
## version the main menu shows.
extends GdUnitTestSuite

const PRESETS: String = "res://export_presets.cfg"


func _presets() -> Dictionary:
	var config := ConfigFile.new()
	assert_int(config.load(PRESETS)).is_equal(OK)
	var by_platform := {}
	for section in config.get_sections():
		if section.count(".") == 1:  # "preset.N", not "preset.N.options"
			by_platform[config.get_value(section, "platform")] = section
	var out := {}
	for platform: String in by_platform:
		var section: String = by_platform[platform]
		out[platform] = {
			"exclude": str(config.get_value(section, "exclude_filter", "")),
			"path": str(config.get_value(section, "export_path", "")),
			"embed": bool(config.get_value(section + ".options", "binary_format/embed_pck", false)),
			"arch": str(config.get_value(section + ".options", "binary_format/architecture", "")),
		}
	return out


func test_windows_and_linux_presets_exist() -> void:
	var presets := _presets()
	assert_bool(presets.has("Windows Desktop")).is_true()
	assert_bool(presets.has("Linux")).is_true()


func test_builds_are_single_files_without_tests_or_tooling() -> void:
	for platform: String in _presets():
		var preset: Dictionary = _presets()[platform]
		assert_bool(preset["embed"]).override_failure_message(platform).is_true()
		assert_str(preset["arch"]).is_equal("x86_64")
		for folder in ["tests/*", "addons/gdUnit4/*", "tools/*", "docs/*"]:
			assert_str(preset["exclude"]).contains(folder)
		assert_str(preset["path"]).starts_with("export/")
	var ignored := FileAccess.get_file_as_string("res://.gitignore")
	assert_str(ignored).contains("/export/")


func test_the_menu_shows_the_version() -> void:
	var semver := RegEx.create_from_string("^\\d+\\.\\d+\\.\\d+")
	assert_object(semver.search(MainMenu.version_text())).is_not_null()
	var menu: MainMenu = auto_free(MainMenu.new())
	add_child(menu)
	var label := menu.find_child("Version", true, false) as Label
	assert_str(label.text).is_equal("v" + MainMenu.version_text())

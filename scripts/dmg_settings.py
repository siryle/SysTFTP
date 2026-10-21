"""Finder layout for unattended DMG builds; matches layout_dmg.applescript."""

from pathlib import Path

project_dir = Path(defines["project_dir"])
app_name = "SysTFTP.app"
applications_name = "应用程序"

format = "UDZO"
filesystem = "HFS+"
files = [str(project_dir / "build" / app_name)]
symlinks = {applications_name: "/Applications"}
icon = str(project_dir / "Assets/SysTFTP.icns")
background = str(project_dir / "Assets/DMG/background.tiff")

window_rect = ((200, 120), (640, 468))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = True
show_item_info = False
arrange_by = None
icon_size = 128
text_size = 15
label_pos = "bottom"
icon_locations = {app_name: (165, 285), applications_name: (475, 285)}

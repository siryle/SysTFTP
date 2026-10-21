on run arguments
    set mountFolder to POSIX file (item 1 of arguments) as alias
    tell application "Finder"
        tell folder mountFolder
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set sidebar width to 0
                -- The content area matches the 640 x 440 background.
                set bounds to {200, 120, 840, 588}
            end tell
            set opts to icon view options of container window
            tell opts
                set arrangement to not arranged
                set icon size to 128
                set text size to 15
                set shows item info to false
                set shows icon preview to true
            end tell
            set background picture of opts to file ".background:background.tiff"
            set position of item "SysTFTP.app" to {165, 285}
            set extension hidden of item "SysTFTP.app" to true
            set position of item "应用程序" to {475, 285}
            update without registering applications
            delay 1
            -- Finder flushes .DS_Store when closing the configured window.
            close container window
        end tell
    end tell
end run

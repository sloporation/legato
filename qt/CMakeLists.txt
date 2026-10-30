cmake_minimum_required(VERSION 3.16)
# The release workflow sets the version from the tag (v1.2.3 → 1.2.3).
set(LEGATO_VERSION "0.1.0" CACHE STRING "Legato's version, shown in the app's Info.plist")
project(legato VERSION ${LEGATO_VERSION} LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Multimedia Network)
# TagLib 2 reads and writes the tags in the music files: macOS `brew install taglib`, Windows `vcpkg install taglib`; on Linux,
# distributions that still ship 1.x (Ubuntu 24.04) need it built from source (see .github/workflows/build.yml).
find_package(TagLib 2.0 REQUIRED)
# Syncing to phones over USB (docs/sync.md): libimobiledevice for iPhones (through usbmuxd), libmtp for Android phones. Either can be
# left out, and the app is built without that kind of phone: macOS `brew install pkgconf libimobiledevice libmtp`; Debian/Ubuntu
# `pkg-config libimobiledevice-dev libmtp-dev`. (Windows has neither yet: libmtp isn't in vcpkg, and Windows talks MTP its own way.)
find_package(PkgConfig)
if(PkgConfig_FOUND)
    pkg_check_modules(IMOBILEDEVICE IMPORTED_TARGET libimobiledevice-1.0 libplist-2.0)
    pkg_check_modules(MTP IMPORTED_TARGET libmtp)
endif()
qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

# The config file (legato.yaml) is read and written in plain C, in core/.
# libyaml: macOS `brew install libyaml`, Debian/Ubuntu `libyaml-dev`,
# Windows `vcpkg install libyaml`. It ships no CMake config, so find it by hand.
find_path(YAML_INCLUDE_DIR yaml.h REQUIRED)
find_library(YAML_LIBRARY NAMES yaml yaml_static REQUIRED)

add_library(legato_core STATIC core/config.c core/config.h)
target_include_directories(legato_core PUBLIC core)
target_include_directories(legato_core PUBLIC ${YAML_INCLUDE_DIR})
target_link_libraries(legato_core PUBLIC ${YAML_LIBRARY})

qt_add_executable(legato main.cpp)

# QML singletons: Tabler (shared font loader + icon table), Theme (colours and sizes).
set_source_files_properties(qml/components/Tabler.qml qml/components/Theme.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# QML module: the .qml files plus the C++ classes exposed to them (the Settings, Library and Player singletons).
qt_add_qml_module(legato
    URI App
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/SettingsWindow.qml
        qml/components/AlbumTile.qml
        qml/components/Card.qml
        qml/components/FindField.qml
        qml/components/Icon.qml
        qml/components/PanelToggle.qml
        qml/components/PlayerBar.qml
        qml/components/Sidebar.qml
        qml/components/SidebarRow.qml
        qml/components/Tabler.qml
        qml/components/TrackInfoDialog.qml
        qml/components/Theme.qml
        qml/components/TrackTable.qml
        qml/components/WheelScroll.qml
        qml/views/AlbumView.qml
        qml/views/AlbumsView.qml
        qml/views/DeviceView.qml
        qml/views/ArtistsView.qml
        qml/views/PlaylistView.qml
        qml/views/SongsView.qml
    RESOURCES fonts/tabler-icons.ttf icons/legato.png
    SOURCES settings.h settings.cpp library.h library.cpp folderwatcher.h folderwatcher.cpp player.h player.cpp
            devices.h devices.cpp devicestorage.h sync.h sync.cpp
)

target_link_libraries(legato PRIVATE legato_core Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia Qt6::Network TagLib::TagLib)
if(IMOBILEDEVICE_FOUND)
    target_sources(legato PRIVATE iphonestorage.h iphonestorage.cpp)
    target_link_libraries(legato PRIVATE PkgConfig::IMOBILEDEVICE)
    target_compile_definitions(legato PRIVATE LEGATO_IPHONE)
else()
    message(STATUS "libimobiledevice not found: building without syncing to iPhones")
endif()
if(MTP_FOUND)
    target_sources(legato PRIVATE androidstorage.h androidstorage.cpp)
    target_link_libraries(legato PRIVATE PkgConfig::MTP)
    target_compile_definitions(legato PRIVATE LEGATO_ANDROID)
else()
    message(STATUS "libmtp not found: building without syncing to Android phones")
endif()
if(APPLE)
    # FSEvents, for noticing changes in the music folders
    target_link_libraries(legato PRIVATE "-framework CoreServices")

    # a proper app: Legato.app, with its icon in Finder and the Dock
    set(LEGATO_ICNS ${CMAKE_CURRENT_SOURCE_DIR}/icons/legato.icns)
    set_source_files_properties(${LEGATO_ICNS} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
    target_sources(legato PRIVATE ${LEGATO_ICNS})
    set_target_properties(legato PROPERTIES
        MACOSX_BUNDLE TRUE
        OUTPUT_NAME Legato
        MACOSX_BUNDLE_BUNDLE_NAME Legato
        MACOSX_BUNDLE_GUI_IDENTIFIER com.sloporation.legato.desktop
        MACOSX_BUNDLE_ICON_FILE legato.icns
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION})
elseif(WIN32)
    # a window, not a console
    set_target_properties(legato PROPERTIES WIN32_EXECUTABLE TRUE)
endif()

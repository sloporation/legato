cmake_minimum_required(VERSION 3.16)
project(legato LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick QuickControls2 Multimedia)
# TagLib reads (and will write) the tags in the music files: macOS `brew install taglib`, Debian/Ubuntu `libtag1-dev` (2.x),
# Windows `vcpkg install taglib`.
find_package(TagLib 2.0 REQUIRED)
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
        qml/components/Card.qml
        qml/components/Icon.qml
        qml/components/PanelToggle.qml
        qml/components/PlayerBar.qml
        qml/components/Sidebar.qml
        qml/components/SidebarRow.qml
        qml/components/Tabler.qml
        qml/components/Theme.qml
        qml/components/TrackTable.qml
        qml/components/WheelScroll.qml
        qml/views/AlbumsView.qml
        qml/views/ArtistsView.qml
        qml/views/PlaylistView.qml
        qml/views/SongsView.qml
    RESOURCES fonts/tabler-icons.ttf
    SOURCES settings.h settings.cpp library.h library.cpp folderwatcher.h folderwatcher.cpp player.h player.cpp
)

target_link_libraries(legato PRIVATE legato_core Qt6::Quick Qt6::QuickControls2 Qt6::Multimedia TagLib::TagLib)
if(APPLE)
    # FSEvents, for noticing changes in the music folders
    target_link_libraries(legato PRIVATE "-framework CoreServices")
endif()

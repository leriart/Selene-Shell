cmake_minimum_required(VERSION 3.24)

project(selene-shell
    VERSION 0.1.0
    DESCRIPTION "Selene -- a QML shell for Hyprland, written in Rust"
    LANGUAGES CXX
)

if(MSVC)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")
endif()

set(CMAKE_AUTOMOC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CXXQT_QTCOMPONENTS Core Gui Qml Quick)

find_package(Qt6 COMPONENTS ${CXXQT_QTCOMPONENTS} QuickControls2 QuickTemplates2 REQUIRED)
set(Qt "Qt6")

find_package(CxxQt QUIET)
if(NOT CxxQt_FOUND)
    include(FetchContent)
    FetchContent_Declare(
        CxxQt
        GIT_REPOSITORY https://github.com/kdab/cxx-qt-cmake.git
        GIT_TAG 0.9.1
    )
    FetchContent_MakeAvailable(CxxQt)
endif()

cxx_qt_import_crate(
    MANIFEST_PATH rust/Cargo.toml
    CRATES selene_shell
    LOCKED
    QT_MODULES Qt::Core Qt::Gui Qt::Qml Qt::Quick Qt::QuickControls2 Qt::QuickTemplates2
)

cxx_qt_import_qml_module(selene_shell_qml_module
    URI "io.github.selene.shell"
    SOURCE_CRATE selene_shell
)

add_executable(selene-shell cpp/main.cpp)
target_link_libraries(selene-shell PRIVATE selene_shell_qml_module)

# mlua embeds Lua via pkg-config; propagate that link to the C++ executable
# so the staticlib's unresolved Lua symbols resolve at link time.
find_package(PkgConfig REQUIRED)
pkg_check_modules(LUA54 REQUIRED IMPORTED_TARGET lua-5.4)
target_link_libraries(selene-shell PRIVATE PkgConfig::LUA54)

qt_import_qml_plugins(selene-shell)

install(TARGETS selene-shell
    RUNTIME DESTINATION bin
)

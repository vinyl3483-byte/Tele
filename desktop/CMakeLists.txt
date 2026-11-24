cmake_minimum_required(VERSION 3.22)
project(telefam_desktop VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick QuickDialogs2 Network)
find_package(Qt6 COMPONENTS Multimedia QUIET)

add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../core ${CMAKE_CURRENT_BINARY_DIR}/telefam_core_build)

qt_add_executable(telefam_desktop
    src/main.cpp
    src/TelefamDesktopController.hpp
    src/TelefamDesktopController.cpp
    resources/resources.qrc
)

qt_add_qml_module(telefam_desktop
    URI TelefamDesktop
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/AuthView.qml
        qml/ProfileSetupView.qml
        qml/WorkspaceView.qml
        qml/ContactsView.qml
        qml/PostThemeCanvas.qml
        qml/PostCreatorView.qml
)

target_link_libraries(telefam_desktop
    PRIVATE
        telefam_core
        Qt6::Core
        Qt6::Gui
        Qt6::Quick
        Qt6::QuickDialogs2
        Qt6::Network
)

if(Qt6Multimedia_FOUND)
    target_link_libraries(telefam_desktop PRIVATE Qt6::Multimedia)
    target_compile_definitions(telefam_desktop PRIVATE TELEFAM_HAS_QT_MULTIMEDIA=1)
endif()

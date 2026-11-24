cmake_minimum_required(VERSION 3.22)
project(telefam_core VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

option(TELEFAM_BUILD_SHARED "Build shared library for JNI/FFI" OFF)

set(TELEFAM_CORE_SOURCES
    src/telefam_crypto.cpp
    src/telefam_engine.cpp
)

if(TELEFAM_BUILD_SHARED)
    add_library(telefam_core SHARED ${TELEFAM_CORE_SOURCES})
else()
    add_library(telefam_core STATIC ${TELEFAM_CORE_SOURCES})
endif()

target_include_directories(telefam_core
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)

target_compile_definitions(telefam_core PRIVATE TELEFAM_CORE_BUILDING=1)

if(MSVC)
    target_compile_options(telefam_core PRIVATE /W4 /O2)
else()
    target_compile_options(telefam_core PRIVATE -Wall -Wextra -Wpedantic -O2 -fvisibility=hidden)
endif()

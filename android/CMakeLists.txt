cmake_minimum_required(VERSION 3.22.1)
project(telefam_android_jni LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(TELEFAM_BUILD_SHARED OFF CACHE BOOL "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../core ${CMAKE_CURRENT_BINARY_DIR}/core_build)

add_library(telefam_core_jni SHARED
    jni/telefam_jni.cpp
)

find_library(log-lib log)

target_link_libraries(telefam_core_jni
    PRIVATE
        telefam_core
        ${log-lib}
)

cmake_minimum_required(VERSION 3.22)
project(telefam_security_engine VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(telefam_security SHARED
    src/security_engine.cpp
    ../../core/src/telefam_crypto.cpp
)

target_include_directories(telefam_security
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../core/include
)

target_compile_options(telefam_security PRIVATE -Wall -Wextra -O2)

cmake_minimum_required(VERSION 3.15)
project(mmg_engine VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Options
option(BUILD_TESTS "Build tests" ON)
option(BUILD_PYTHON_BINDINGS "Build Python bindings" ON)

# Engine library
add_library(mmg_engine
    src/order_book.cpp
    src/engine.cpp
)

target_include_directories(mmg_engine
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)

target_compile_options(mmg_engine PRIVATE
    $<$<CXX_COMPILER_ID:GNU,Clang,AppleClang>:-Wall -Wextra -Wpedantic -O3>
    $<$<CXX_COMPILER_ID:MSVC>:/W4 /O2>
)

# Tests
if(BUILD_TESTS)
    enable_testing()
    
    # Download and setup Google Test
    include(FetchContent)
    FetchContent_Declare(
        googletest
        GIT_REPOSITORY https://github.com/google/googletest.git
        GIT_TAG release-1.12.1
    )
    FetchContent_MakeAvailable(googletest)
    
    add_executable(mmg_engine_tests
        tests/test_order_book.cpp
        tests/test_engine.cpp
        tests/test_pnl.cpp
    )
    
    target_link_libraries(mmg_engine_tests
        mmg_engine
        gtest_main
    )
    
    include(GoogleTest)
    gtest_discover_tests(mmg_engine_tests)
endif()

# Python bindings
if(BUILD_PYTHON_BINDINGS)
    find_package(Python3 COMPONENTS Interpreter Development REQUIRED)
    
    # Try to find pybind11
    find_package(pybind11 CONFIG)
    if(NOT pybind11_FOUND)
        FetchContent_Declare(
            pybind11
            GIT_REPOSITORY https://github.com/pybind/pybind11.git
            GIT_TAG v2.11.1
        )
        FetchContent_MakeAvailable(pybind11)
    endif()
    
    pybind11_add_module(mmg_engine_py
        bindings/python_bindings.cpp
    )
    
    target_link_libraries(mmg_engine_py PRIVATE mmg_engine)
    
    # Set output name to mmg_engine (without .py suffix)
    set_target_properties(mmg_engine_py PROPERTIES OUTPUT_NAME mmg_engine)
endif()

# Installation
install(TARGETS mmg_engine
    EXPORT mmg_engineTargets
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(DIRECTORY include/ DESTINATION include)


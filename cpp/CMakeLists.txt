cmake_minimum_required(VERSION 3.16)
project(call-coding-clis LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(ccc_lib
  src/build_prompt.cpp
  src/config.cpp
  src/help.cpp
  src/parser.cpp
  src/runner.cpp
)
target_include_directories(ccc_lib PUBLIC include)

add_executable(ccc src/ccc_cli.cpp)
target_link_libraries(ccc PRIVATE ccc_lib)

option(CCC_BUILD_TESTS "Build tests" ON)
if(CCC_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()

install(TARGETS ccc RUNTIME DESTINATION bin)
install(TARGETS ccc_lib ARCHIVE DESTINATION lib)
install(DIRECTORY include/ccc DESTINATION include)

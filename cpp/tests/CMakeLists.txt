include(FetchContent)
FetchContent_Declare(googletest
  GIT_REPOSITORY https://github.com/google/googletest.git
  GIT_TAG v1.14.0
)
set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(googletest)

add_executable(ccc_tests
  test_prompt_spec.cpp
  test_runner.cpp
  test_ccc_contract.cpp
  test_parser.cpp
)
target_link_libraries(ccc_tests PRIVATE ccc_lib GTest::gtest_main)
include(GoogleTest)
gtest_discover_tests(ccc_tests)

# GaussVector-component 对接目录（变异产物）
set(GAUSSVECTOR_INSTALL_DIR ${VECTOR_HOME})

# 查找 libannlite.so
find_library(ANNLITE_LIB annlite
    PATHS ${GAUSSVECTOR_INSTALL_DIR}/lib
    NO_DEFAULT_PATH)
if(NOT ANNLITE_LIB)
    message(FATAL_ERROR "libannlite.so not found in ${GAUSSVECTOR_INSTALL_DIR}/lib, please add it first")
endif()
message(STATUS "Found annlite: ${ANNLITE_LIB}")

set(TGT_gv_index_INC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/env
    ${GAUSSVECTOR_INSTALL_DIR}/include
)

set(gv_index_DEF_OPTIONS ${MACRO_OPTIONS} -DANN_LITE_BINARY_MODE=1)

set(gv_index_COMPILE_OPTIONS ${OPTIMIZE_OPTIONS} ${OS_OPTIONS} ${PROTECT_OPTIONS} ${WARNING_OPTIONS} ${BIN_SECURE_OPTIONS} ${CHECK_OPTIONS}
    -std=c++17 -D_GLIBCXX_USE_CXX11_ABI=0 -fPIC -fstack-protector-all)
set(gv_index_LINK_OPTIONS ${BIN_LINK_OPTIONS})

FILE(GLOB_RECURSE TGT_gv_index_SRC
    "${CMAKE_CURRENT_SOURCE_DIR}/*.cpp"
)
add_shared_libtarget(gv_index TGT_gv_index_SRC TGT_gv_index_INC "${gv_index_DEF_OPTIONS}" "${gv_index_COMPILE_OPTIONS}" "${gv_index_LINK_OPTIONS}")

# 链接 libannlite.so
target_link_libraries(gv_index PRIVATE ${ANNLITE_LIB})

# 设置 RPATH 以便运行时能找到 libannlite.so
file(RELATIVE_PATH _rel_path ${CMAKE_INSTALL_PREFIX}/lib ${GAUSSVECTOR_INSTALL_DIR}/lib)
target_link_options(gv_index PRIVATE -Wl,-rpath,'$ORIGIN/../${_rel_path}')

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/gv_index.control ${CMAKE_CURRENT_SOURCE_DIR}/gv_index--1.0.sql
    DESTINATION share/postgresql/extension/
    PERMISSIONS OWNER_WRITE OWNER_READ)
install(TARGETS gv_index LIBRARY DESTINATION lib/postgresql
    PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ
)
# 安装 libannlite.so 到 install/lib 目录
install(FILES ${ANNLITE_LIB} DESTINATION lib
    PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE
)
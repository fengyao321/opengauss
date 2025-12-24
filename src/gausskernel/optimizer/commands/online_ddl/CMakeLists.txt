#This is the main CMAKE for build all components.
AUX_SOURCE_DIRECTORY(${CMAKE_CURRENT_SOURCE_DIR} TGT_online_ddl_SRC)

set(TGT_online_ddl_INC
    ${PROJECT_SRC_DIR}/include/libcomm
    ${PROJECT_SRC_DIR}/include
    ${EVENT_INCLUDE_PATH}
    ${LIBCURL_INCLUDE_PATH}
)

set(online_ddl_DEF_OPTIONS ${MACRO_OPTIONS})
set(online_ddl_COMPILE_OPTIONS ${OPTIMIZE_OPTIONS} ${OS_OPTIONS} ${PROTECT_OPTIONS} ${WARNING_OPTIONS} ${BIN_SECURE_OPTIONS} ${CHECK_OPTIONS})
set(online_ddl_LINK_OPTIONS ${BIN_LINK_OPTIONS})
add_static_objtarget(gausskernel_optimizer_commands_online_ddl TGT_online_ddl_SRC TGT_online_ddl_INC "${online_ddl_DEF_OPTIONS}" "${online_ddl_COMPILE_OPTIONS}" "${online_ddl_LINK_OPTIONS}")

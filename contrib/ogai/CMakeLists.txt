# This is the main CMAKE for build ogai extension
# ogai.so

AUX_SOURCE_DIRECTORY(${CMAKE_CURRENT_SOURCE_DIR} TGT_ogai_SRC)

SET(TGT_ogai_INC
    ${CMAKE_CURRENT_SOURCE_DIR}
)

set(ogai_DEF_OPTIONS ${MACRO_OPTIONS})
set(ogai_COMPILE_OPTIONS ${OPTIMIZE_OPTIONS} ${OS_OPTIONS} ${PROTECT_OPTIONS} ${WARNING_OPTIONS} ${LIB_SECURE_OPTIONS} ${CHECK_OPTIONS})
set(ogai_LINK_OPTIONS ${LIB_LINK_OPTIONS})

add_shared_libtarget(ogai TGT_ogai_SRC TGT_ogai_INC "${ogai_DEF_OPTIONS}" "${ogai_COMPILE_OPTIONS}" "${ogai_LINK_OPTIONS}")
set_target_properties(ogai PROPERTIES PREFIX "")

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/ogai.control
    DESTINATION share/postgresql/extension/
)
install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/ogai--1.0.sql
    DESTINATION share/postgresql/extension/
)

install(TARGETS ogai DESTINATION lib/postgresql)

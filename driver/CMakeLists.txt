option(LPAC_WITH_APDU_PCSC "Build APDU PCSC Backend (requires PCSC libraries)" ON)
option(LPAC_WITH_APDU_AT "Build APDU AT Backend" OFF)
option(LPAC_WITH_APDU_GBINDER "Build APDU Gbinder backend for libhybris devices (requires gbinder headers)" OFF)
option(LPAC_WITH_APDU_QMI "Build QMI backend for Qualcomm devices (requires libqmi)" OFF)
option(LPAC_WITH_APDU_QMI_QRTR "Build QMI-over-QRTR backend for Qualcomm devices (requires libqrtr and libqmi headers)" OFF)
option(LPAC_WITH_APDU_UQMI "Build uQMI backend for Qualcomm devices (requires uqmi)" OFF)
option(LPAC_WITH_APDU_MBIM "Build MBIM backend for MBIM devices (requires libmbim)" OFF)

option(LPAC_WITH_HTTP_CURL "Build HTTP Curl interface" ON)
cmake_dependent_option(LPAC_WITH_HTTP_WINHTTP "Build HTTP WinHTTP interface (Win32 only)" ON WIN32 OFF)

if (LPAC_STATIC_DRIVERS)
    set(DRIVER_LIB_TYPE OBJECT)
    if (LPAC_WITH_APDU_GBINDER OR LPAC_WITH_APDU_QMI
        OR LPAC_WITH_APDU_QMI_QRTR OR LPAC_WITH_APDU_UQMI OR LPAC_WITH_APDU_MBIM)
        message(FATAL_ERROR "LPAC_STATIC_DRIVERS only supports stdio, AT, curl and pcsc drivers.")
    endif ()
else ()
    set(DRIVER_LIB_TYPE SHARED)
endif ()

# Shared mode: install the driver as a plugin. Built-in mode: rename its driver_if and link it into the loader.
macro(lpac_finish_driver target name)
    if (LPAC_STATIC_DRIVERS)
        target_compile_definitions(${target} PRIVATE driver_if=driver_if_${name})
        list(APPEND LPAC_STATIC_DRIVER_NAMES ${name})
        list(APPEND LPAC_STATIC_DRIVER_TARGETS ${target})
    else ()
        set_target_properties(${target} PROPERTIES PREFIX "")
        install(TARGETS ${target} LIBRARY DESTINATION ${DRIVER_INSTALL_PATH})
    endif ()
endmacro()

add_library(euicc-drivers ${LPAC_LIB_TYPE})
set_target_properties(euicc-drivers PROPERTIES LINKER_LANGUAGE C)
target_sources(
    euicc-drivers
    PUBLIC
        FILE_SET public_headers
        TYPE HEADERS
        BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}
        FILES
            driver.h
)

add_library(euicc-driver-loader ${LPAC_LIB_TYPE})
target_link_libraries(euicc-driver-loader PRIVATE euicc euicc-drivers ${DL_LIBRARY} ${CJSON_LIBRARY} lpac-utils)
target_sources(
    euicc-driver-loader
    PRIVATE
        euicc-driver-loader.c
)
target_sources(
    euicc-driver-loader
    PUBLIC
        FILE_SET public_headers
        TYPE HEADERS
        BASE_DIRS ${CMAKE_CURRENT_SOURCE_DIR}
        FILES
            euicc-driver-loader.h
)

# Only useful on Windows, and will lead to invalid arguments on ld.gold.
if(WIN32)
    target_link_options(euicc-driver-loader PRIVATE "LINKER:--export-all-symbols")
endif()

add_library(driver_apdu_stdio ${DRIVER_LIB_TYPE} apdu/stdio.c)
target_link_libraries(driver_apdu_stdio PRIVATE euicc euicc-drivers cjson-ext lpac-utils)
lpac_finish_driver(driver_apdu_stdio apdu_stdio)

add_library(driver_http_stdio ${DRIVER_LIB_TYPE} http/stdio.c)
target_link_libraries(driver_http_stdio PRIVATE euicc euicc-drivers cjson-ext lpac-utils)
lpac_finish_driver(driver_http_stdio http_stdio)

if (LPAC_WITH_APDU_PCSC)
    add_library(driver_apdu_pcsc ${DRIVER_LIB_TYPE} ${CMAKE_CURRENT_SOURCE_DIR}/apdu/pcsc.c)
    target_link_libraries(driver_apdu_pcsc PRIVATE euicc euicc-drivers cjson-ext lpac-utils)
    if (WIN32)
        target_sources(driver_apdu_pcsc PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/apdu/pcsc_win32.c)
        target_link_libraries(driver_apdu_pcsc PRIVATE winscard)
    elseif (APPLE)
        target_link_libraries(driver_apdu_pcsc PRIVATE "-framework PCSC")
    else ()
        find_package(PCSCLite REQUIRED)
        target_link_libraries(driver_apdu_pcsc PRIVATE PCSCLite::PCSCLite)
        if (LPAC_STATIC_DRIVERS)
            target_link_libraries(euicc-driver-loader PRIVATE PCSCLite::PCSCLite)
        endif ()
    endif ()
    lpac_finish_driver(driver_apdu_pcsc apdu_pcsc)
endif ()

if (LPAC_WITH_APDU_AT)
    message(WARNING "LPAC_WITH_APDU_AT is NO LONGER MAINTAINED and maybe REMOVED in future releases.")

    if (LPAC_STATIC_DRIVERS)
        # at and at_csim share helpers; build them once to avoid duplicate symbols.
        add_library(driver_apdu_at_common OBJECT
            ${CMAKE_CURRENT_SOURCE_DIR}/apdu/at_helpers.c
            ${CMAKE_CURRENT_SOURCE_DIR}/apdu/at_cmd_unix.c
        )
        target_include_directories(driver_apdu_at_common PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
        target_link_libraries(driver_apdu_at_common PRIVATE euicc euicc-drivers cjson-ext lpac-utils)
        list(APPEND LPAC_STATIC_DRIVER_TARGETS driver_apdu_at_common)
    endif ()

    function(add_at_driver target_name extra_sources)
        add_library(${target_name} ${DRIVER_LIB_TYPE} ${extra_sources})
        target_include_directories(${target_name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
        target_link_libraries(${target_name} PRIVATE euicc euicc-drivers cjson-ext lpac-utils)

        if (NOT LPAC_STATIC_DRIVERS)
            target_sources(${target_name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/apdu/at_helpers.c)
            if (UNIX)
                target_sources(${target_name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/apdu/at_cmd_unix.c)
            elseif (WIN32)
                target_link_libraries(${target_name} PRIVATE setupapi)
                target_sources(${target_name} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/apdu/at_cmd_win32.c)
            else ()
                message(FATAL_ERROR "${target_name} is only supported on Unix and Windows platforms.")
            endif ()
        endif ()
    endfunction()

    add_at_driver(driver_apdu_at "${CMAKE_CURRENT_SOURCE_DIR}/apdu/at_etsi.c")
    lpac_finish_driver(driver_apdu_at apdu_at)

    add_at_driver(driver_apdu_at_csim "${CMAKE_CURRENT_SOURCE_DIR}/apdu/at_etsi_csim.c")
    lpac_finish_driver(driver_apdu_at_csim apdu_at_csim)
endif ()

if(LPAC_WITH_APDU_GBINDER)
    add_library(driver_apdu_gbinder SHARED ${CMAKE_CURRENT_SOURCE_DIR}/apdu/gbinder_hidl.c)
    target_link_libraries(driver_apdu_gbinder PRIVATE euicc euicc-drivers lpac-utils)
    set_target_properties(driver_apdu_gbinder PROPERTIES PREFIX "")
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(GBINDER REQUIRED IMPORTED_TARGET libgbinder)
    pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0)
    target_link_libraries(driver_apdu_gbinder PRIVATE PkgConfig::GBINDER PkgConfig::GLIB)
    install(TARGETS driver_apdu_gbinder LIBRARY DESTINATION ${DRIVER_INSTALL_PATH})
endif()

if (LPAC_WITH_APDU_QMI OR LPAC_WITH_APDU_QMI_QRTR)
    add_library(qmi_common OBJECT
            ${CMAKE_CURRENT_SOURCE_DIR}/apdu/qmi_helpers.c
            ${CMAKE_CURRENT_SOURCE_DIR}/apdu/qmi_common.c)
    target_link_libraries(qmi_common PRIVATE cjson euicc euicc-drivers lpac-utils)

    find_package(PkgConfig REQUIRED)
    pkg_check_modules(QMI_GLIB REQUIRED IMPORTED_TARGET qmi-glib>=1.36.0)
    target_link_libraries(qmi_common PUBLIC PkgConfig::QMI_GLIB)
endif ()

if (LPAC_WITH_APDU_QMI)
    add_library(driver_apdu_qmi SHARED ${CMAKE_CURRENT_SOURCE_DIR}/apdu/qmi.c)
    target_link_libraries(driver_apdu_qmi PRIVATE cjson euicc euicc-drivers qmi_common lpac-utils)
    set_target_properties(driver_apdu_qmi PROPERTIES PREFIX "")
    target_compile_definitions(qmi_common PRIVATE LPAC_WITH_DRIVER_APDU_QMI)
    target_compile_definitions(driver_apdu_qmi PRIVATE LPAC_WITH_DRIVER_APDU_QMI)
    install(TARGETS driver_apdu_qmi LIBRARY DESTINATION ${DRIVER_INSTALL_PATH})
endif ()

if (LPAC_WITH_APDU_QMI_QRTR)
    add_library(driver_apdu_qmi_qrtr SHARED ${CMAKE_CURRENT_SOURCE_DIR}/apdu/qmi_qrtr.c)
    target_link_libraries(driver_apdu_qmi_qrtr PRIVATE cjson euicc euicc-drivers qmi_common lpac-utils)
    set_target_properties(driver_apdu_qmi_qrtr PROPERTIES PREFIX "")
    target_compile_definitions(qmi_common PRIVATE LPAC_WITH_DRIVER_APDU_QMI_QRTR)
    target_compile_definitions(driver_apdu_qmi_qrtr PRIVATE LPAC_WITH_DRIVER_APDU_QMI_QRTR)
    install(TARGETS driver_apdu_qmi_qrtr LIBRARY DESTINATION ${DRIVER_INSTALL_PATH})
endif ()

if (LPAC_WITH_APDU_UQMI)
    add_library(driver_apdu_uqmi SHARED ${CMAKE_CURRENT_SOURCE_DIR}/apdu/uqmi.c)
    target_link_libraries(driver_apdu_uqmi PRIVATE euicc euicc-drivers lpac-utils)
    target_compile_options(driver_apdu_uqmi PRIVATE -Wvla -Wconversion)
    set_target_properties(driver_apdu_uqmi PROPERTIES PREFIX "")

    include(CheckSymbolExists)
    check_symbol_exists(pidfd_spawn "spawn.h" HAVE_PIDFD_SPAWN)
    check_symbol_exists(P_PIDFD "linux/wait.h" HAVE_WAITID_PIDFD)
    if (HAVE_PIDFD_SPAWN AND HAVE_WAITID_PIDFD)
        target_compile_definitions(driver_apdu_uqmi PRIVATE HAVE_PIDFD)
    endif ()

    install(TARGETS driver_apdu_uqmi LIBRARY DESTINATION ${DRIVER_INSTALL_PATH})
endif ()

if (LPAC_WITH_APDU_MBIM)
    add_library(driver_apdu_mbim SHARED
            ${CMAKE_CURRENT_SOURCE_DIR}/apdu/mbim.c
            ${CMAKE_CURRENT_SOURCE_DIR}/apdu/mbim_helpers.c)
    target_link_libraries(driver_apdu_mbim PRIVATE euicc euicc-drivers lpac-utils)
    set_target_properties(driver_apdu_mbim PROPERTIES PREFIX "")

    find_package(PkgConfig REQUIRED)
    pkg_check_modules(MBIM_GLIB REQUIRED IMPORTED_TARGET mbim-glib>=1.26.0)
    target_link_libraries(driver_apdu_mbim PRIVATE PkgConfig::MBIM_GLIB PkgConfig::MBIM_GLIB)

    install(TARGETS driver_apdu_mbim LIBRARY DESTINATION ${DRIVER_INSTALL_PATH})
endif ()

if(LPAC_WITH_HTTP_CURL)
    add_library(driver_http_curl ${DRIVER_LIB_TYPE} ${CMAKE_CURRENT_SOURCE_DIR}/http/curl.c)
    target_link_libraries(driver_http_curl PRIVATE euicc euicc-drivers lpac-utils)
    if(WIN32)
        target_link_libraries(driver_http_curl PRIVATE ${DL_LIBRARY})
    else()
        find_package(CURL REQUIRED COMPONENTS HTTPS)
        target_link_libraries(driver_http_curl PRIVATE CURL::libcurl)
        if (LPAC_STATIC_DRIVERS)
            # Object libraries don't link; hand libcurl to the loader.
            target_link_libraries(euicc-driver-loader PRIVATE CURL::libcurl)
        endif ()
    endif()
    lpac_finish_driver(driver_http_curl http_curl)
endif()

if (LPAC_WITH_HTTP_WINHTTP)
    add_library(driver_http_winhttp SHARED ${CMAKE_CURRENT_SOURCE_DIR}/http/winhttp.c)
    target_link_libraries(driver_http_winhttp PRIVATE winhttp euicc euicc-drivers lpac-utils)
    set_target_properties(driver_http_winhttp PROPERTIES PREFIX "")
    install(TARGETS driver_http_winhttp LIBRARY DESTINATION ${DRIVER_INSTALL_PATH})
endif ()

if (LPAC_STATIC_DRIVERS)
    set(_decls "")
    set(_table "")
    foreach (_name IN LISTS LPAC_STATIC_DRIVER_NAMES)
        string(APPEND _decls "extern const struct euicc_driver driver_if_${_name};\n")
        string(APPEND _table "    &driver_if_${_name},\n")
    endforeach ()
    file(CONFIGURE OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/static_drivers.h @ONLY CONTENT
"#pragma once\n#include \"driver.h\"\n@_decls@\nstatic const struct euicc_driver *const static_drivers[] = {\n@_table@    NULL,\n};\n")
    target_include_directories(euicc-driver-loader PRIVATE ${CMAKE_CURRENT_BINARY_DIR})
    target_compile_definitions(euicc-driver-loader PRIVATE LPAC_STATIC_DRIVERS)
    foreach (_target IN LISTS LPAC_STATIC_DRIVER_TARGETS)
        target_sources(euicc-driver-loader PRIVATE $<TARGET_OBJECTS:${_target}>)
    endforeach ()
endif ()

# Install a pkg-config file (mainly for Linux; macOS is untested; Win32 is not supported)
if(UNIX AND NOT STANDALONE_MODE)
    list(APPEND LIBEUICC_DRIVER_LOADER_REQUIRES "libeuicc = ${PROJECT_VERSION}")
    configure_file(libeuicc-driver-loader.pc.in libeuicc-driver-loader.pc @ONLY)
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/libeuicc-driver-loader.pc DESTINATION ${CMAKE_INSTALL_LIBDIR}/pkgconfig)
endif()
set_target_properties(euicc-drivers PROPERTIES SOVERSION ${PROJECT_VERSION_MAJOR})
if (NOT LPAC_STATIC_DRIVERS)
    install(TARGETS euicc-drivers LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})
endif ()
set_target_properties(euicc-driver-loader PROPERTIES SOVERSION ${PROJECT_VERSION_MAJOR})
install(TARGETS euicc-driver-loader LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
                                    FILE_SET public_headers DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

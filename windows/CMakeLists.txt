cmake_minimum_required(VERSION 3.20)
project(KuroCat LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(KuroCat WIN32
    src/main.cpp
    src/KeyMap.hpp
    src/InputEngine.hpp
    src/CatPhysics.hpp
    src/CatRenderer.hpp
    src/MiniJson.hpp
    src/SoundEngine.hpp
    src/MusicPulse.hpp
    src/WasapiGuids.hpp
    app.manifest
)

target_compile_definitions(KuroCat PRIVATE UNICODE _UNICODE NOMINMAX COBJMACROS)
if(MSVC)
    target_compile_options(KuroCat PRIVATE /O2 /utf-8 /EHsc /W3 /MT)
else()
    target_compile_options(KuroCat PRIVATE -O2 -municode -pthread -finput-charset=UTF-8 -fexec-charset=UTF-8)
    target_link_options(KuroCat PRIVATE -Wl,--subsystem,windows)
endif()

target_link_libraries(KuroCat PRIVATE
    user32 gdi32 gdiplus shell32 advapi32 ole32 uuid avrt
)

# Ship the same seven WAV themes used by the macOS build.
add_custom_command(TARGET KuroCat POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/../Resources/SoundThemes"
        "$<TARGET_FILE_DIR:KuroCat>/SoundThemes"
    COMMENT "Bundling SoundThemes next to KuroCat.exe"
)

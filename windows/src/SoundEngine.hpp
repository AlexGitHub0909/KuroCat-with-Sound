#pragma once

// Keyboard sound engine for the Windows build of KuroCat.
// Port of the macOS KuroSoundEngine: same themes, same key categories, same
// 12-voice round-robin pool, but playback goes through WASAPI instead of
// AVAudioEngine. Samples are the unmodified 16-bit PCM WAV files shipped with
// the macOS build; they are decoded into memory and mixed on the fly.

#define NOMINMAX
#define COBJMACROS
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <avrt.h>
#include <objbase.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <mutex>
#include <random>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "KeyMap.hpp"
#include "MiniJson.hpp"
#include "WasapiGuids.hpp"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "uuid.lib")
#pragma comment(lib, "avrt.lib")

#ifndef WAVE_FORMAT_EXTENSIBLE
#define WAVE_FORMAT_EXTENSIBLE 0xFFFE
#endif
#ifndef WAVE_FORMAT_IEEE_FLOAT
#define WAVE_FORMAT_IEEE_FLOAT 0x0003
#endif

// KSDATAFORMAT_SUBTYPE_IEEE_FLOAT {00000003-0000-0010-8000-00AA00389B71}
static const GUID KuroGuidIeeeFloat = {
    0x00000003, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71 }
};

enum class SoundCategory : int {
    Standard = 0,
    Space,
    Enter,
    Delete,
    Escape,
    Arrow,
    Modifier,
    Count
};

inline SoundCategory soundCategoryFor(PhysicalKey key) {
    switch (key) {
        case PhysicalKey::Space: return SoundCategory::Space;
        case PhysicalKey::Enter: return SoundCategory::Enter;
        case PhysicalKey::Backspace:
        case PhysicalKey::ForwardDelete: return SoundCategory::Delete;
        case PhysicalKey::Escape: return SoundCategory::Escape;
        case PhysicalKey::ArrowUp:
        case PhysicalKey::ArrowDown:
        case PhysicalKey::ArrowLeft:
        case PhysicalKey::ArrowRight: return SoundCategory::Arrow;
        case PhysicalKey::LeftShift:
        case PhysicalKey::RightShift:
        case PhysicalKey::LeftControl:
        case PhysicalKey::RightControl:
        case PhysicalKey::LeftOption:
        case PhysicalKey::RightOption:
        case PhysicalKey::LeftCommand:
        case PhysicalKey::RightCommand:
        case PhysicalKey::CapsLock:
        case PhysicalKey::Fn: return SoundCategory::Modifier;
        default: return SoundCategory::Standard;
    }
}

inline std::wstring utf8ToWide(const std::string& text) {
    if (text.empty()) return L"";
    int len = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.c_str(), (int)text.size(), nullptr, 0);
    if (len <= 0) return L"";
    std::wstring out((size_t)len, L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.c_str(), (int)text.size(), &out[0], len);
    return out;
}

inline std::string readTextFile(const std::wstring& path) {
    std::ifstream f(path.c_str(), std::ios::binary);
    if (!f) return std::string();
    return std::string(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
}

class KuroSoundEngine {
public:
    static constexpr int VoiceCount = 12;

    struct ThemeInfo {
        std::string id;
        std::wstring displayName;
    };

    static KuroSoundEngine& instance() {
        static KuroSoundEngine engine;
        return engine;
    }

    KuroSoundEngine() = default;
    ~KuroSoundEngine() { shutdown(); }

    KuroSoundEngine(const KuroSoundEngine&) = delete;
    KuroSoundEngine& operator=(const KuroSoundEngine&) = delete;

    /// Discovers themes under <root>/SoundThemes and loads the selected one.
    /// Audio output is optional: if no render device exists the engine still
    /// exposes the theme list and simply stays silent.
    void initialize(const std::wstring& exeDir, bool enabled,
                    const std::string& themeId, double volume) {
        std::lock_guard<std::mutex> lock(mutex_);
        volume_ = std::clamp(volume, 0.0, 4.0);
        enabled_ = enabled;
        themesRoot_ = findThemesRoot(exeDir);
        if (themesRoot_.empty()) {
            lastError_ = L"找不到 SoundThemes 音效资源目录";
            return;
        }
        discoverThemesLocked();
        loadThemeLocked(themeId);
        if (enabled_ && !samples_.empty()) startOutputLocked();
    }

    void shutdown() {
        stopOutput();
        std::lock_guard<std::mutex> lock(mutex_);
        samples_.clear();
        for (auto& list : categorySamples_) list.clear();
    }

    void setEnabled(bool enabled) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (enabled_ == enabled) return;
            enabled_ = enabled;
            if (!enabled) {
                for (auto& v : voices_) v.sampleIndex = -1;
            }
        }
        if (enabled) {
            std::lock_guard<std::mutex> lock(mutex_);
            if (samples_.empty() && !currentThemeId_.empty()) loadThemeLocked(currentThemeId_);
            if (!samples_.empty()) startOutputLocked();
        } else {
            stopOutput();
        }
    }

    void setVolume(double volume) {
        std::lock_guard<std::mutex> lock(mutex_);
        volume_ = std::clamp(volume, 0.0, 4.0);
    }

    bool setTheme(const std::string& id) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            if (id == currentThemeId_ && !samples_.empty()) return true;
            for (auto& v : voices_) v.sampleIndex = -1;
        }
        stopOutput();
        std::lock_guard<std::mutex> lock(mutex_);
        loadThemeLocked(id);
        if (enabled_ && !samples_.empty()) startOutputLocked();
        return !samples_.empty();
    }

    void play(SoundCategory category) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!enabled_ || !outputRunning_ || samples_.empty()) return;
        const auto standardIdx = (int)SoundCategory::Standard;
        int cat = (int)category;
        if (cat < 0 || cat >= (int)SoundCategory::Count) cat = standardIdx;
        const auto& pool = categorySamples_[cat].empty() ? categorySamples_[standardIdx] : categorySamples_[cat];
        if (pool.empty()) return;

        static thread_local std::mt19937 rng{(unsigned)std::random_device{}()};
        std::uniform_int_distribution<size_t> pick(0, pool.size() - 1);
        Voice& voice = voices_[nextVoice_];
        nextVoice_ = (nextVoice_ + 1) % VoiceCount;
        voice.sampleIndex = pool[pick(rng)];
        voice.position = 0.0;
    }

    std::vector<ThemeInfo> themes() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return themes_;
    }

    std::wstring currentThemeName() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return currentThemeName_;
    }

    std::wstring lastError() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return lastError_;
    }

private:
    struct WaveSample {
        std::vector<float> data; // mono, normalized -1..1
        double sampleRate = 48000.0;
    };

    struct Voice {
        int sampleIndex = -1;
        double position = 0.0;
    };

    mutable std::mutex mutex_;
    std::wstring themesRoot_;
    std::vector<ThemeInfo> themes_;
    std::string currentThemeId_;
    std::wstring currentThemeName_;
    std::wstring lastError_;
    std::vector<WaveSample> samples_;
    std::array<std::vector<int>, (int)SoundCategory::Count> categorySamples_;
    std::array<Voice, VoiceCount> voices_;
    int nextVoice_ = 0;
    bool enabled_ = true;
    double volume_ = 1.0;

    // WASAPI render state, owned by the audio thread after start.
    IMMDeviceEnumerator* enumerator_ = nullptr;
    IMMDevice* renderDevice_ = nullptr;
    IAudioClient* audioClient_ = nullptr;
    IAudioRenderClient* renderClient_ = nullptr;
    std::vector<BYTE> mixFormat_;
    UINT32 bufferFrames_ = 0;
    DWORD outputRate_ = 48000;
    WORD outputChannels_ = 2;
    bool outputFloat_ = false;
    WORD outputBits_ = 16;
    bool outputRunning_ = false;
    std::thread outputThread_;
    std::atomic<bool> outputStop_{false};

    static std::wstring joinPath(const std::wstring& a, const std::string& b) {
        std::wstring tail = utf8ToWide(b);
        std::wstring dir = a;
        if (!dir.empty() && dir.back() != L'\\' && dir.back() != L'/') dir += L'\\';
        return dir + tail;
    }

    static bool fileExists(const std::wstring& path) {
        DWORD attr = GetFileAttributesW(path.c_str());
        return attr != INVALID_FILE_ATTRIBUTES && !(attr & FILE_ATTRIBUTE_DIRECTORY);
    }

    static std::wstring findThemesRoot(const std::wstring& exeDir) {
        std::wstring candidates[] = {
            exeDir + L"\\SoundThemes",
            exeDir + L"\\..\\SoundThemes",
            exeDir + L"\\..\\..\\Resources\\SoundThemes",
            L"SoundThemes",
            L"Resources\\SoundThemes"
        };
        for (const auto& dir : candidates) {
            if (fileExists(joinPath(dir, "catalog.json"))) return dir;
        }
        return L"";
    }

    void discoverThemesLocked() {
        themes_.clear();
        std::string catalogText = readTextFile(joinPath(themesRoot_, "catalog.json"));
        MiniJson::Value catalog;
        if (!MiniJson::parse(catalogText, catalog)) {
            lastError_ = L"无法读取音效主题目录 catalog.json";
            return;
        }
        const MiniJson::Value* dirs = catalog.find("themeDirectories");
        if (!dirs || !dirs->isArray()) {
            lastError_ = L"音效主题目录格式错误";
            return;
        }
        for (const auto& entry : dirs->array) {
            if (!entry.isString()) continue;
            std::string manifestText = readTextFile(joinPath(joinPath(themesRoot_, entry.text), "theme.json"));
            MiniJson::Value manifest;
            if (!MiniJson::parse(manifestText, manifest)) continue;
            const MiniJson::Value* id = manifest.find("id");
            const MiniJson::Value* name = manifest.find("displayName");
            if (!id || !id->isString()) continue;
            std::wstring display = name && name->isString() ? utf8ToWide(name->text) : utf8ToWide(id->text);
            themes_.push_back({id->text, display});
        }
    }

    static bool parseWave(const std::vector<BYTE>& bytes, WaveSample& out) {
        if (bytes.size() < 44 || std::memcmp(bytes.data(), "RIFF", 4) != 0 ||
            std::memcmp(bytes.data() + 8, "WAVE", 4) != 0) return false;

        size_t dataOffset = 0, dataSize = 0;
        WORD channels = 0, bits = 0, formatTag = 0;
        DWORD rate = 0;
        for (size_t p = 12; p + 8 <= bytes.size();) {
            uint32_t chunkSize = 0;
            for (int i = 0; i < 4; ++i) chunkSize |= ((uint32_t)bytes[p + 4 + i]) << (8 * i);
            size_t body = p + 8;
            if (body + chunkSize > bytes.size()) break;
            if (std::memcmp(bytes.data() + p, "fmt ", 4) == 0 && chunkSize >= 16) {
                formatTag = (WORD)(bytes[body] | (bytes[body + 1] << 8));
                channels = (WORD)(bytes[body + 2] | (bytes[body + 3] << 8));
                rate = 0;
                for (int i = 0; i < 4; ++i) rate |= ((DWORD)bytes[body + 4 + i]) << (8 * i);
                bits = (WORD)(bytes[body + 14] | (bytes[body + 15] << 8));
            } else if (std::memcmp(bytes.data() + p, "data", 4) == 0) {
                dataOffset = body;
                dataSize = chunkSize;
            }
            p = body + chunkSize + (chunkSize & 1u);
        }
        if (formatTag != 1 || channels == 0 || bits != 16 || rate == 0 || dataSize == 0) return false;
        if (dataOffset + dataSize > bytes.size()) return false;

        const int16_t* pcm = reinterpret_cast<const int16_t*>(bytes.data() + dataOffset);
        size_t frames = dataSize / (2u * channels);
        out.data.resize(frames);
        for (size_t i = 0; i < frames; ++i) {
            // All shipped samples are mono; downmix defensively if not.
            double sum = 0.0;
            for (WORD c = 0; c < channels; ++c) sum += pcm[i * channels + c] / 32768.0;
            out.data[i] = (float)(sum / channels);
        }
        out.sampleRate = (double)rate;
        return !out.data.empty();
    }

    void loadThemeLocked(const std::string& id) {
        samples_.clear();
        for (auto& list : categorySamples_) list.clear();
        currentThemeId_ = id;
        currentThemeName_.clear();
        lastError_.clear();

        std::wstring dir = joinPath(themesRoot_, id);
        std::string manifestText = readTextFile(joinPath(dir, "theme.json"));
        MiniJson::Value manifest;
        if (!MiniJson::parse(manifestText, manifest)) {
            lastError_ = L"找不到音效主题：" + utf8ToWide(id);
            return;
        }
        const MiniJson::Value* name = manifest.find("displayName");
        if (name && name->isString()) currentThemeName_ = utf8ToWide(name->text);
        const MiniJson::Value* categories = manifest.find("categories");
        if (!categories || !categories->isObject()) {
            lastError_ = L"音效主题格式错误";
            return;
        }

        static const char* categoryNames[] = {
            "standard", "space", "enter", "delete", "escape", "arrow", "modifier"
        };
        for (int c = 0; c < (int)SoundCategory::Count; ++c) {
            const MiniJson::Value* paths = categories->find(categoryNames[c]);
            if (!paths || !paths->isArray()) continue;
            for (const auto& pathValue : paths->array) {
                if (!pathValue.isString()) continue;
                std::wstring samplePath = joinPath(dir, pathValue.text);
                std::ifstream f(samplePath.c_str(), std::ios::binary);
                if (!f) continue;
                std::vector<BYTE> bytes((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
                WaveSample sample;
                if (!parseWave(bytes, sample)) continue;
                categorySamples_[c].push_back((int)samples_.size());
                samples_.push_back(std::move(sample));
            }
        }
        if (samples_.empty() || categorySamples_[(int)SoundCategory::Standard].empty()) {
            lastError_ = L"音效主题没有可播放样本";
            samples_.clear();
            for (auto& list : categorySamples_) list.clear();
        }
    }

    void startOutputLocked() {
        if (outputRunning_) return;
        HRESULT hr = CoCreateInstance(KuroClsidMMDeviceEnumerator, nullptr, CLSCTX_ALL,
                                      KuroIidIMMDeviceEnumerator, (void**)&enumerator_);
        if (FAILED(hr) || !enumerator_) {
            lastError_ = L"无法初始化 Windows 音频设备";
            releaseOutputLocked();
            return;
        }
        hr = enumerator_->GetDefaultAudioEndpoint(eRender, eMultimedia, &renderDevice_);
        if (FAILED(hr) || !renderDevice_) {
            lastError_ = L"找不到默认播放设备";
            releaseOutputLocked();
            return;
        }
        hr = renderDevice_->Activate(KuroIidIAudioClient, CLSCTX_ALL, nullptr, (void**)&audioClient_);
        if (FAILED(hr) || !audioClient_) {
            lastError_ = L"无法打开默认播放设备";
            releaseOutputLocked();
            return;
        }
        WAVEFORMATEX* mix = nullptr;
        hr = audioClient_->GetMixFormat(&mix);
        if (FAILED(hr) || !mix) {
            lastError_ = L"无法读取音频格式";
            releaseOutputLocked();
            return;
        }
        size_t bytes = sizeof(WAVEFORMATEX) + mix->cbSize;
        mixFormat_.assign((BYTE*)mix, (BYTE*)mix + bytes);
        CoTaskMemFree(mix);
        const WAVEFORMATEX& fmt = *(const WAVEFORMATEX*)mixFormat_.data();
        outputChannels_ = fmt.nChannels;
        outputRate_ = fmt.nSamplesPerSec;
        outputBits_ = fmt.wBitsPerSample;
        outputFloat_ = false;
        if (fmt.wFormatTag == WAVE_FORMAT_EXTENSIBLE && mixFormat_.size() >= sizeof(WAVEFORMATEXTENSIBLE)) {
            const auto& ext = *(const WAVEFORMATEXTENSIBLE*)mixFormat_.data();
            outputFloat_ = (IsEqualGUID(ext.SubFormat, KuroGuidIeeeFloat) != FALSE);
        } else {
            outputFloat_ = (fmt.wFormatTag == WAVE_FORMAT_IEEE_FLOAT);
        }
        if (!outputFloat_ && outputBits_ != 16 && outputBits_ != 24 && outputBits_ != 32) {
            lastError_ = L"不支持的音频格式";
            releaseOutputLocked();
            return;
        }
        hr = audioClient_->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_NOPERSIST,
                                      2'000'000, 0, &fmt, nullptr);
        if (FAILED(hr)) {
            lastError_ = L"无法启动音频输出 (HRESULT " + std::to_wstring((long)hr) + L")";
            releaseOutputLocked();
            return;
        }
        hr = audioClient_->GetBufferSize(&bufferFrames_);
        if (FAILED(hr)) {
            releaseOutputLocked();
            return;
        }
        hr = audioClient_->GetService(KuroIidIAudioRenderClient, (void**)&renderClient_);
        if (FAILED(hr) || !renderClient_) {
            lastError_ = L"无法获取音频渲染接口";
            releaseOutputLocked();
            return;
        }

        outputRunning_ = true;
        outputStop_ = false;
        outputThread_ = std::thread([this]() { renderLoop(); });
        lastError_.clear();
    }

    void stopOutput() {
        std::thread oldThread;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            outputStop_ = true;
            outputRunning_ = false;
            if (outputThread_.joinable()) oldThread = std::move(outputThread_);
        }
        // Never join while holding mutex_: the render thread takes it for mixing.
        if (oldThread.joinable()) oldThread.join();
        std::lock_guard<std::mutex> lock(mutex_);
        if (audioClient_) audioClient_->Stop();
        releaseOutputLocked();
    }

    void releaseOutputLocked() {
        if (renderClient_) { renderClient_->Release(); renderClient_ = nullptr; }
        if (audioClient_) { audioClient_->Release(); audioClient_ = nullptr; }
        if (renderDevice_) { renderDevice_->Release(); renderDevice_ = nullptr; }
        if (enumerator_) { enumerator_->Release(); enumerator_ = nullptr; }
        mixFormat_.clear();
        bufferFrames_ = 0;
    }

    static float readInterp(const WaveSample& s, double pos) {
        size_t i = (size_t)pos;
        if (i >= s.data.size()) return 0.0f;
        float a = s.data[i];
        if (i + 1 >= s.data.size()) return a;
        float frac = (float)(pos - (double)i);
        return a + (s.data[i + 1] - a) * frac;
    }

    // Padé tanh approximation: keeps 150-200% volume loud but never hard-clips.
    static float softLimit(float x) {
        float x2 = x * x;
        return x * (27.0f + x2) / (27.0f + 9.0f * x2);
    }

    void renderLoop() {
        HRESULT comHr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        const bool comInitialized = SUCCEEDED(comHr);
        DWORD taskIndex = 0;
        HANDLE mmTask = AvSetMmThreadCharacteristicsW(L"Pro Audio", &taskIndex);

        UINT32 localFrames = bufferFrames_;
        DWORD localRate = outputRate_;
        WORD localChannels = outputChannels_;
        WORD localBits = outputBits_;
        bool localFloat = outputFloat_;
        IAudioClient* client = audioClient_;
        IAudioRenderClient* renderer = renderClient_;
        if (client) client->Start();

        int consecutiveErrors = 0;
        while (!outputStop_) {
            UINT32 padding = 0;
            HRESULT hr = client ? client->GetCurrentPadding(&padding) : E_FAIL;
            if (FAILED(hr)) {
                if (++consecutiveErrors > 50) break;
                Sleep(20);
                continue;
            }
            consecutiveErrors = 0;
            UINT32 available = localFrames > padding ? localFrames - padding : 0;
            if (available == 0) {
                Sleep(2);
                continue;
            }
            BYTE* buffer = nullptr;
            hr = renderer ? renderer->GetBuffer(available, &buffer) : E_FAIL;
            if (FAILED(hr) || !buffer) {
                if (++consecutiveErrors > 50) break;
                Sleep(20);
                continue;
            }

            const double gain = volume_ * 0.85;
            for (UINT32 frame = 0; frame < available; ++frame) {
                float mono = 0.0f;
                {
                    std::lock_guard<std::mutex> lock(mutex_);
                    for (auto& voice : voices_) {
                        if (voice.sampleIndex < 0 || voice.sampleIndex >= (int)samples_.size()) continue;
                        const WaveSample& s = samples_[voice.sampleIndex];
                        if (voice.position >= (double)s.data.size()) { voice.sampleIndex = -1; continue; }
                        mono += readInterp(s, voice.position);
                        voice.position += s.sampleRate / std::max(1.0, (double)localRate);
                        if (voice.position >= (double)s.data.size()) voice.sampleIndex = -1;
                    }
                }
                float value = softLimit(mono * (float)gain);
                for (WORD ch = 0; ch < localChannels; ++ch) {
                    size_t offset = ((size_t)frame * localChannels + ch);
                    if (localFloat) {
                        float* dst = (float*)buffer + offset;
                        *dst = value;
                    } else if (localBits == 16) {
                        int16_t* dst = ((int16_t*)buffer) + offset;
                        *dst = (int16_t)std::clamp((int)(value * 32767.0f), -32768, 32767);
                    } else if (localBits == 32) {
                        int32_t* dst = ((int32_t*)buffer) + offset;
                        *dst = (int32_t)std::clamp((double)(value * 2147483647.0), -2147483648.0, 2147483647.0);
                    } else { // 24-bit packed
                        int v = (int)std::clamp((int)(value * 8388607.0f), -8388608, 8388607) & 0xFFFFFF;
                        BYTE* dst = buffer + offset * 3;
                        dst[0] = (BYTE)(v & 0xFF); dst[1] = (BYTE)((v >> 8) & 0xFF); dst[2] = (BYTE)((v >> 16) & 0xFF);
                    }
                }
            }
            renderer->ReleaseBuffer(available, 0);
            Sleep(1);
        }
        if (client) client->Stop();
        if (mmTask) AvRevertMmThreadCharacteristics(mmTask);
        if (comInitialized) CoUninitialize();
    }
};

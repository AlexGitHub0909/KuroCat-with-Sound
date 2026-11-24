#pragma once

// Music Pulse for the Windows build of KuroCat.
// macOS uses Core Audio Process Taps; Windows uses a WASAPI loopback client on
// the default render endpoint. The DSP is deliberately identical to
// Sources/Sound/MusicPulse.swift: six cascaded one-pole low-pass differences,
// the same attack/release smoothing, beat threshold and peak decay.
//
// Audio is analysed in memory only. Nothing is recorded, stored or uploaded.

#define NOMINMAX
#define COBJMACROS
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <objbase.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

#include "InputEngine.hpp" // nowSeconds()
#include "WasapiGuids.hpp"

#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "uuid.lib")

#ifndef WAVE_FORMAT_EXTENSIBLE
#define WAVE_FORMAT_EXTENSIBLE 0xFFFE
#endif
#ifndef WAVE_FORMAT_IEEE_FLOAT
#define WAVE_FORMAT_IEEE_FLOAT 0x0003
#endif
static const GUID KuroPulseIeeeFloat = {
    0x00000003, 0x0000, 0x0010, { 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71 }
};

class MusicPulse {
public:
    static constexpr int BandCount = 6;
    // Cutoff coefficients from deep bass upward (matches MusicPulse.swift).
    static constexpr float BandAlphas[BandCount] = { 0.012f, 0.028f, 0.065f, 0.14f, 0.30f, 0.62f };
    static constexpr float BandGains[BandCount]  = { 3.2f, 3.6f, 4.4f, 5.4f, 6.8f, 8.5f };

    static MusicPulse& instance() {
        static MusicPulse pulse;
        return pulse;
    }

    MusicPulse() = default;
    ~MusicPulse() { stop(); }
    MusicPulse(const MusicPulse&) = delete;
    MusicPulse& operator=(const MusicPulse&) = delete;

    void setEnabled(bool value) {
        if (value) start();
        else stop();
    }

    bool enabled() const { return enabled_.load(); }
    bool isPlaying() const {
        std::lock_guard<std::mutex> lock(stateMutex_);
        return isPlaying_;
    }

    struct Snapshot {
        double level = 0.0;
        double bass = 0.0;
        double beat = 0.0;
        bool playing = false;
        float bands[BandCount] = {};
        float peaks[BandCount] = {};
        std::wstring error;
    };

    Snapshot snapshot() const {
        std::lock_guard<std::mutex> lock(stateMutex_);
        Snapshot s;
        s.level = level_;
        s.bass = bass_;
        s.beat = beat_;
        s.playing = isPlaying_;
        s.error = lastError_;
        for (int i = 0; i < BandCount; ++i) {
            s.bands[i] = (float)bands_[i];
            s.peaks[i] = (float)bandPeaks_[i];
        }
        return s;
    }

    /// Called by the key sound engine so our own key clicks do not drive the
    /// spectrum (the macOS build excludes its own process from the tap).
    void suppressOwnSound(double seconds = 0.18) {
        double until = nowSeconds() + seconds;
        double prev = suppressUntil_.load();
        while (until > prev && !suppressUntil_.compare_exchange_weak(prev, until)) {}
    }

    /// Called from the 60 fps render loop (one call per frame is fine).
    void poll() {
        const double now = nowSeconds();
        double dt = now - lastPollTime_;
        lastPollTime_ = now;
        if (dt < 0.0 || dt > 0.2) dt = 1.0 / 60.0;

        Metrics m;
        {
            std::lock_guard<std::mutex> lock(metricsMutex_);
            m = metrics_;
        }

        if (!enabled_.load()) return;
        if (m.callbacks == 0 && now - startCheckTime_ > 3.0) {
            std::lock_guard<std::mutex> lock(stateMutex_);
            if (lastError_.empty()) {
                lastError_ = L"未收到系统音频：请确认正在播放声音，且默认输出设备正确";
            }
        }

        const bool fresh = m.callbacks != lastCallbackCount_;
        lastCallbackCount_ = m.callbacks;

        if (m.rms > 0.004f) lastLoudTime_ = now;
        const bool playing = fresh && (now - lastLoudTime_) < 1.2;

        if (playing) {
            float target = std::min(1.0f, m.rms * 3.4f);
            smoothedLevel_ += (target - smoothedLevel_) * (target > smoothedLevel_ ? 0.35f : 0.06f);
            float bassTarget = std::min(1.0f, m.bass * 5.5f);
            smoothedBass_ += (bassTarget - smoothedBass_) * (bassTarget > smoothedBass_ ? 0.40f : 0.07f);
            runningBassAverage_ += (m.bass - runningBassAverage_) * 0.015f;
            if (m.bass > runningBassAverage_ * 1.45f && m.bass > 0.012f && now - lastBeatTime_ > 0.20) {
                beatEnvelope_ = 1.0;
                lastBeatTime_ = now;
            }
            std::lock_guard<std::mutex> lock(stateMutex_);
            if (!lastError_.empty()) lastError_.clear();
        } else {
            smoothedLevel_ += (0.0f - smoothedLevel_) * 0.08f;
            smoothedBass_ += (0.0f - smoothedBass_) * 0.08f;
        }
        beatEnvelope_ *= 0.82;

        std::lock_guard<std::mutex> lock(stateMutex_);
        level_ = playing ? smoothedLevel_ : 0.0;
        bass_ = playing ? smoothedBass_ : 0.0;
        beat_ = playing ? beatEnvelope_ : 0.0;
        isPlaying_ = playing;

        for (int i = 0; i < BandCount; ++i) {
            float target = playing ? std::min(1.0f, m.bands[i] * BandGains[i]) : 0.0f;
            float rate = target > bands_[i] ? 0.85f : 0.26f;
            bands_[i] += (target - bands_[i]) * rate;
            if (bands_[i] >= bandPeaks_[i]) bandPeaks_[i] = bands_[i];
            else bandPeaks_[i] = std::max(bands_[i], bandPeaks_[i] - 0.055f);
        }
    }

private:
    struct Metrics {
        float rms = 0.0f;
        float bass = 0.0f;
        uint64_t callbacks = 0;
        float bands[BandCount] = {};
    };

    std::atomic<bool> enabled_{false};
    std::atomic<bool> captureStop_{false};
    std::atomic<double> suppressUntil_{0.0};

    mutable std::mutex stateMutex_;
    double level_ = 0.0, bass_ = 0.0, beat_ = 0.0;
    float bands_[BandCount] = {};
    float bandPeaks_[BandCount] = {};
    bool isPlaying_ = false;
    std::wstring lastError_;

    mutable std::mutex metricsMutex_;
    Metrics metrics_;

    std::thread captureThread_;
    double lastPollTime_ = 0.0;
    double lastLoudTime_ = 0.0;
    double lastBeatTime_ = 0.0;
    double startCheckTime_ = 0.0;
    uint64_t lastCallbackCount_ = 0;
    float smoothedLevel_ = 0.0f;
    float smoothedBass_ = 0.0f;
    float runningBassAverage_ = 0.0f;
    float beatEnvelope_ = 0.0f;

    void start() {
        if (enabled_.exchange(true)) return;
        {
            std::lock_guard<std::mutex> lock(stateMutex_);
            lastError_.clear();
        }
        {
            std::lock_guard<std::mutex> lock(metricsMutex_);
            metrics_ = Metrics();
        }
        lastCallbackCount_ = 0;
        lastLoudTime_ = 0.0;
        lastBeatTime_ = 0.0;
        smoothedLevel_ = smoothedBass_ = runningBassAverage_ = beatEnvelope_ = 0.0f;
        startCheckTime_ = nowSeconds();
        lastPollTime_ = startCheckTime_;
        captureStop_ = false;
        captureThread_ = std::thread([this]() { captureLoop(); });
    }

    void stop() {
        if (!enabled_.exchange(false)) {
            if (!captureThread_.joinable()) return;
        }
        captureStop_ = true;
        if (captureThread_.joinable()) captureThread_.join();
        {
            std::lock_guard<std::mutex> lock(stateMutex_);
            level_ = bass_ = beat_ = 0.0;
            isPlaying_ = false;
            for (int i = 0; i < BandCount; ++i) { bands_[i] = 0.0f; bandPeaks_[i] = 0.0f; }
        }
        {
            std::lock_guard<std::mutex> lock(metricsMutex_);
            metrics_ = Metrics();
        }
        lastCallbackCount_ = 0;
        smoothedLevel_ = smoothedBass_ = runningBassAverage_ = beatEnvelope_ = 0.0f;
        lastLoudTime_ = 0.0;
    }

    void setError(const std::wstring& message) {
        std::lock_guard<std::mutex> lock(stateMutex_);
        if (enabled_.load()) lastError_ = message;
    }

    void captureLoop() {
        HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
        const bool comInitialized = SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE;

        IMMDeviceEnumerator* enumerator = nullptr;
        IMMDevice* device = nullptr;
        IAudioClient* client = nullptr;
        IAudioCaptureClient* capture = nullptr;
        WAVEFORMATEX* mixFormat = nullptr;
        bool started = false;

        do {
            hr = CoCreateInstance(KuroClsidMMDeviceEnumerator, nullptr, CLSCTX_ALL,
                                  KuroIidIMMDeviceEnumerator, (void**)&enumerator);
            if (FAILED(hr) || !enumerator) { setError(L"无法初始化 Windows 音频设备"); break; }
            hr = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device);
            if (FAILED(hr) || !device) { setError(L"找不到默认播放设备（音乐律动需要它做 Loopback）"); break; }
            hr = device->Activate(KuroIidIAudioClient, CLSCTX_ALL, nullptr, (void**)&client);
            if (FAILED(hr) || !client) { setError(L"无法打开系统音频 Loopback"); break; }
            hr = client->GetMixFormat(&mixFormat);
            if (FAILED(hr) || !mixFormat) { setError(L"无法读取系统音频格式"); break; }

            hr = client->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                    AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_NOPERSIST,
                                    10000000, 0, mixFormat, nullptr);
            if (FAILED(hr)) { setError(L"无法启动系统音频采集 (HRESULT " + std::to_wstring((long)hr) + L")"); break; }
            hr = client->GetService(KuroIidIAudioCaptureClient, (void**)&capture);
            if (FAILED(hr) || !capture) { setError(L"无法获取音频采集接口"); break; }
            hr = client->Start();
            if (FAILED(hr)) { setError(L"无法开始采集系统音频"); break; }
            started = true;
        } while (false);

        if (started) {
            const WORD channels = mixFormat->nChannels;
            const DWORD rate = mixFormat->nSamplesPerSec;
            const WORD bits = mixFormat->wBitsPerSample;
            bool isFloat = false;
            if (mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
                const auto& ext = *(const WAVEFORMATEXTENSIBLE*)mixFormat;
                isFloat = (IsEqualGUID(ext.SubFormat, KuroPulseIeeeFloat) != FALSE);
            } else {
                isFloat = (mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT);
            }
            // Scratch DSP state lives entirely on the capture thread.
            float lowPass = 0.0f;
            float lowpasses[BandCount] = {};

            while (!captureStop_) {
                UINT32 packetFrames = 0;
                if (FAILED(capture->GetNextPacketSize(&packetFrames)) || packetFrames == 0) {
                    Sleep(5);
                    continue;
                }
                BYTE* data = nullptr;
                UINT32 frames = 0;
                DWORD flags = 0;
                UINT64 position = 0, timestamp = 0;
                hr = capture->GetBuffer(&data, &frames, &flags, &position, &timestamp);
                if (FAILED(hr) || !data || frames == 0) {
                    Sleep(5);
                    continue;
                }

                Metrics local;
                {
                    std::lock_guard<std::mutex> lock(metricsMutex_);
                    local = metrics_;
                }
                const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
                const bool suppressed = nowSeconds() < suppressUntil_.load();
                if (!silent && !suppressed && frames > 0 && channels > 0 && rate > 0) {
                    double sumSquares = 0.0;
                    double bassSquares = 0.0;
                    double energies[BandCount] = {};
                    for (UINT32 i = 0; i < frames; ++i) {
                        double x = 0.0;
                        for (WORD c = 0; c < channels; ++c) {
                            size_t idx = (size_t)i * channels + c;
                            if (isFloat) x += ((const float*)data)[idx];
                            else if (bits == 16) x += ((const int16_t*)data)[idx] / 32768.0;
                            else if (bits == 32) x += ((const int32_t*)data)[idx] / 2147483648.0;
                            else if (bits == 24) {
                                const BYTE* p = data + idx * 3;
                                int v = p[0] | (p[1] << 8) | (p[2] << 16);
                                if (v & 0x800000) v |= ~0xFFFFFF;
                                x += v / 8388608.0;
                            }
                        }
                        x /= channels;
                        sumSquares += x * x;
                        lowPass += 0.045f * ((float)x - lowPass);
                        bassSquares += lowPass * lowPass;
                        float prev = 0.0f;
                        for (int k = 0; k < BandCount; ++k) {
                            lowpasses[k] += BandAlphas[k] * ((float)x - lowpasses[k]);
                            float e = lowpasses[k] - prev;
                            energies[k] += (double)e * e;
                            prev = lowpasses[k];
                        }
                    }
                    local.rms = (float)std::sqrt(sumSquares / frames);
                    local.bass = (float)std::sqrt(bassSquares / frames);
                    for (int k = 0; k < BandCount; ++k) {
                        local.bands[k] = (float)std::sqrt(energies[k] / frames);
                    }
                    local.callbacks++;
                } else if (!suppressed && !silent) {
                    local.callbacks++;
                }
                {
                    std::lock_guard<std::mutex> lock(metricsMutex_);
                    metrics_ = local;
                }
                capture->ReleaseBuffer(frames);
            }
            client->Stop();
        }

        if (capture) capture->Release();
        if (mixFormat) CoTaskMemFree(mixFormat);
        if (client) client->Release();
        if (device) device->Release();
        if (enumerator) enumerator->Release();
        if (comInitialized) CoUninitialize();
    }
};

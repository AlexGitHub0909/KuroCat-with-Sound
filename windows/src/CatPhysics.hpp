#pragma once
#define NOMINMAX
#include <windows.h>
#include <cmath>
#include <vector>
#include <unordered_map>
#include <random>
#include <algorithm>
#include <string>
#include "KeyMap.hpp"
#include "InputEngine.hpp"
#include "MusicPulse.hpp"

enum class CatCoatTheme : int {
    ClassicBlack = 0,
    Siamese = 1,
    Pink = 2
};

enum class KeyboardTheme : int {
    ClassicMilk = 0,
    MidnightHacker = 1,
    RetroCream = 2
};

enum class EyeColorTheme : int {
    NeonChartreuse = 0,
    SiameseBlue = 1,
    WarmAmber = 2,
    IceCyan = 3
};

struct CatSettings {
    bool showKeyBadges = true;
    bool footEasterEgg = true;
    bool petInteraction = true;
    bool fullClickThrough = false;
    bool alwaysOnTop = true;
    float scale = 1.0f;
    CatCoatTheme coatTheme = CatCoatTheme::ClassicBlack;
    KeyboardTheme keyboardTheme = KeyboardTheme::ClassicMilk;
    EyeColorTheme eyeTheme = EyeColorTheme::NeonChartreuse;
    int posX = -99999;
    int posY = -99999;

    // Features added by KuroCat-with-Sound (mirrored from the macOS build).
    bool soundEnabled = true;
    std::string soundTheme = "scissor";
    double soundVolume = 1.0;   // 0...4
    bool musicMode = false;

    void loadFromRegistry() {
        HKEY hKey = nullptr;
        if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\KuroCat", 0, KEY_READ, &hKey) != ERROR_SUCCESS) return;
        auto readDword = [&](const wchar_t* name, DWORD defVal) -> DWORD {
            DWORD val = defVal, sz = sizeof(val);
            if (RegQueryValueExW(hKey, name, nullptr, nullptr, (LPBYTE)&val, &sz) == ERROR_SUCCESS) return val;
            return defVal;
        };
        showKeyBadges    = readDword(L"ShowKeyBadges", 1) != 0;
        footEasterEgg    = readDword(L"FootEasterEgg", 1) != 0;
        petInteraction   = readDword(L"PetInteraction", 1) != 0;
        fullClickThrough = readDword(L"FullClickThrough", 0) != 0;
        alwaysOnTop      = readDword(L"AlwaysOnTop", 1) != 0;
        scale            = std::clamp((float)readDword(L"ScalePct", 100) / 100.0f, 0.5f, 2.0f);
        coatTheme        = (CatCoatTheme)std::clamp((int)readDword(L"CoatTheme", 0), 0, 2);
        keyboardTheme    = (KeyboardTheme)std::clamp((int)readDword(L"KeyboardTheme", 0), 0, 2);
        eyeTheme         = (EyeColorTheme)std::clamp((int)readDword(L"EyeTheme", 0), 0, 3);

        auto readString = [&](const char* name, const std::string& def) -> std::string {
            char buf[256] = {};
            DWORD size = sizeof(buf) - 1;
            if (RegQueryValueExA(hKey, name, nullptr, nullptr, (LPBYTE)buf, &size) == ERROR_SUCCESS) {
                buf[size < sizeof(buf) - 1 ? size : sizeof(buf) - 1] = '\0';
                return std::string(buf);
            }
            return def;
        };
        soundEnabled     = readDword(L"SoundEnabled", 1) != 0;
        soundTheme       = readString("SoundTheme", "scissor");
        soundVolume      = std::clamp((double)readDword(L"SoundVolumePermille", 1000) / 1000.0, 0.0, 4.0);
        musicMode        = readDword(L"MusicMode", 0) != 0;

        DWORD hasPos     = readDword(L"HasPos", 0);
        if (hasPos) {
            posX = (int)readDword(L"PosX", 0);
            posY = (int)readDword(L"PosY", 0);
        }
        RegCloseKey(hKey);
    }

    void saveToRegistry() const {
        HKEY hKey = nullptr;
        if (RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\KuroCat", 0, nullptr, 0, KEY_WRITE, nullptr, &hKey, nullptr) != ERROR_SUCCESS) return;
        auto writeDword = [&](const wchar_t* name, DWORD val) {
            RegSetValueExW(hKey, name, 0, REG_DWORD, (const BYTE*)&val, sizeof(val));
        };
        writeDword(L"ShowKeyBadges", showKeyBadges ? 1 : 0);
        writeDword(L"FootEasterEgg", footEasterEgg ? 1 : 0);
        writeDword(L"PetInteraction", petInteraction ? 1 : 0);
        writeDword(L"FullClickThrough", fullClickThrough ? 1 : 0);
        writeDword(L"AlwaysOnTop", alwaysOnTop ? 1 : 0);
        writeDword(L"ScalePct", (DWORD)(scale * 100.0f + 0.5f));
        writeDword(L"CoatTheme", (DWORD)coatTheme);
        writeDword(L"KeyboardTheme", (DWORD)keyboardTheme);
        writeDword(L"EyeTheme", (DWORD)eyeTheme);
        writeDword(L"SoundEnabled", soundEnabled ? 1 : 0);
        RegSetValueExA(hKey, "SoundTheme", 0, REG_SZ, (const BYTE*)soundTheme.c_str(), (DWORD)(soundTheme.size() + 1));
        writeDword(L"SoundVolumePermille", (DWORD)std::clamp(soundVolume * 1000.0 + 0.5, 0.0, 4000.0));
        writeDword(L"MusicMode", musicMode ? 1 : 0);
        if (posX != -99999 && posY != -99999) {
            writeDword(L"HasPos", 1);
            writeDword(L"PosX", (DWORD)posX);
            writeDword(L"PosY", (DWORD)posY);
        }
        RegCloseKey(hKey);
    }
};

struct Spring1D {
    float value = 0.0f;
    float velocity = 0.0f;
    float target = 0.0f;

    explicit Spring1D(float v = 0.0f) : value(v), velocity(0.0f), target(v) {}

    void step(float dt, float stiffness = 260.0f, float damping = 22.0f) {
        float force = (target - value) * stiffness;
        float damp = velocity * damping;
        velocity += (force - damp) * dt;
        value += velocity * dt;
    }
};

struct Spring2D {
    Spring1D x;
    Spring1D y;

    explicit Spring2D(Pt p = {0.0f, 0.0f}) : x(p.x), y(p.y) {}
    Pt point() const { return { x.value, y.value }; }
    void setTarget(Pt p) { x.target = p.x; y.target = p.y; }
    void step(float dt, float stiffness = 340.0f, float damping = 25.0f) {
        x.step(dt, stiffness, damping);
        y.step(dt, stiffness, damping);
    }
};

struct FloatingKeycap {
    std::wstring label;
    Pt position;
    Pt velocity;
    float age = 0.0f;
    float lifetime = 1.25f;
    float rotation = 0.0f;
};

struct PurrSparkle {
    Pt position;
    Pt velocity;
    float age = 0.0f;
    float lifetime = 0.9f;
    bool isSleepZ = false;
};

/// Music-note particle floating up with the beat (matches Swift MusicNoteParticle).
struct MusicNoteParticle {
    Pt position;
    Pt velocity;
    float age = 0.0f;
    float lifetime = 1.5f;
    int glyph = 0;
    float rotation = 0.0f;
    float scale = 1.0f;
};

/// Manga-style steam wisp emitted while the cat is "fried" from fast typing.
struct SmokePuff {
    Pt position;
    Pt velocity;
    float age = 0.0f;
    float lifetime = 1.3f;
    float radius = 8.0f;
    float seed = 0.0f;
};

class CatPhysics {
public:
    static constexpr float CanvasWidth  = 360.0f;
    static constexpr float CanvasHeight = 320.0f;
    static constexpr Pt SeatAnchor      = { 184.0f, 226.0f };
    static constexpr Pt LeftPawRest     = { 164.0f, 235.0f };
    static constexpr Pt RightPawRest    = { 204.0f, 235.0f };
    static constexpr Pt HindFootRest    = { 214.0f, 234.0f };
    static constexpr Pt MouseBaseCenter = { 78.0f, 258.0f };

    Spring2D leftPaw{LeftPawRest};
    Spring2D rightPaw{RightPawRest};
    Spring2D hindFoot{HindFootRest};
    Spring1D hindFootActive{0.0f};

    Spring1D bodyShiftX{0.0f};
    Spring1D bodyTilt{0.0f};
    Spring1D bodySquash{1.0f};
    Spring1D headTilt{0.0f};
    Spring1D headYaw{0.0f};
    Spring1D headPitch{0.0f};
    Spring1D headOffsetY{0.0f};
    Spring1D earFold{0.0f};
    Spring1D earTwitch{0.0f};

    Spring2D eyeGaze{{0.0f, 0.0f}};
    Spring1D pupilScale{1.0f};
    Spring1D huntIntensity{0.0f};
    Spring2D mouseOffset{{0.0f, 0.0f}};
    Spring1D mousePressLeft{0.0f};
    Spring1D mousePressRight{0.0f};

    bool leftPawOnMouse = false;
    bool leftPawTyping = false;
    bool rightPawTyping = false;

    std::unordered_map<PhysicalKey, float> keyGlow;
    std::vector<FloatingKeycap> floatingKeycaps;
    std::vector<PurrSparkle> sparkles;

    // Music-mode overlay state (copied from MusicPulse once per physics step).
    struct PulseState {
        double level = 0.0;
        double bass = 0.0;
        double beat = 0.0;
        bool playing = false;
        float bands[MusicPulse::BandCount] = {};
        float peaks[MusicPulse::BandCount] = {};
    } pulse;

    float equalizerPresence = 0.0f;   // fade-in of the spectrum capsules
    float musicBounce = 0.0f;         // bass/beat head bob
    float musicBlinkBoost = 0.0f;     // happy squint on beats
    std::vector<MusicNoteParticle> musicNotes;

    // Typing overload easter egg.
    float strain = 0.0f;
    bool isFried = false;
    float friedTimeLeft = 0.0f;
    std::vector<SmokePuff> smokePuffs;

    float time = 0.0f;
    float tailPhase = 0.0f;

    float petHeadIntensity = 0.0f;
    float petBodyIntensity = 0.0f;
    int totalPetSessions = 0;
    float sleepiness = 0.0f;

    float effectiveEyeClosure() const {
        float petClose = std::max(petHeadIntensity, petBodyIntensity * 0.62f);
        float sleepClose = sleepiness * 0.92f;
        float musicClose = musicBlinkBoost * 0.52f;
        return std::min(1.0f, std::max(blinkProgress_, std::max(petClose, std::max(sleepClose, musicClose))));
    }

    bool isHappyClosedEyes() const { return petHeadIntensity > 0.45f; }
    bool isBlissfulSquint() const { return petBodyIntensity > 0.35f && !isHappyClosedEyes(); }
    bool isStraining() const { return strain > 0.42f && !isFried && !isHappyClosedEyes(); }
    int strainTier() const {
        if (!isStraining()) return 0;
        if (strain < 0.64f) return 1;
        if (strain < 0.85f) return 2;
        return 3;
    }
    bool isDazed() const { return isFried; }

    void triggerKeyDown(PhysicalKey key, const CatSettings& settings) {
        double now = nowSeconds();
        PhysicalKey vk = visualKeyOf(key);
        keyGlow[vk] = 1.0f;

        // Any fresh keystroke snaps the cat out of the dazed state.
        if (isFried) endFried(now);

        keyTimes_.push_back(now);
        if (keyTimes_.size() > 64) {
            keyTimes_.erase(keyTimes_.begin(), keyTimes_.end() - 64);
        }

        Pt pt = KeyboardLayout::canvasPointForKey(vk);
        hasLastTypedPoint_ = true;
        lastTypedPoint_ = pt;

        if (prefersViewerLeftPaw(key)) {
            recentLeftKey_ = vk;
            recentLeftTime_ = now;
            leftPaw.y.velocity -= 180.0f;
        } else {
            recentRightKey_ = vk;
            recentRightTime_ = now;
            rightPaw.y.velocity -= 180.0f;
        }

        bodySquash.velocity -= 1.3f;
        earTwitch.velocity += (prefersViewerLeftPaw(key) ? -3.8f : 3.8f);
        headTilt.velocity += (prefersViewerLeftPaw(key) ? -1.4f : 1.4f);
        pupilScale.target = 1.16f;
        sleepiness = 0.0f;

        if (settings.showKeyBadges) {
            spawnFloatingKeycap(keyBadgeLabel(key), pt, now);
        }
    }

    void triggerMouseClick(int button, bool isDown) {
        sleepiness = 0.0f;
        if (isDown) {
            if (button == 0) {
                mousePressLeft.target = 1.0f;
                leftPaw.y.velocity += 130.0f;
            } else {
                mousePressRight.target = 1.0f;
                leftPaw.y.velocity += 110.0f;
            }
            pupilScale.target = 1.12f;
            earTwitch.velocity -= 2.2f;
        } else {
            if (button == 0) mousePressLeft.target = 0.0f;
            else mousePressRight.target = 0.0f;
        }
    }

    void registerPetStroke(Pt canvasPoint, float delta, bool isHead, const CatSettings& settings) {
        if (!settings.petInteraction) return;
        double now = nowSeconds();
        lastPetTime_ = now;
        sleepiness = 0.0f;

        float energy = std::min(delta / 26.0f, 0.35f);
        if (isHead) {
            petHeadIntensity = std::min(1.0f, petHeadIntensity + energy + 0.08f);
            petBodyIntensity = std::max(petBodyIntensity, petHeadIntensity * 0.6f);
        } else {
            petBodyIntensity = std::min(1.0f, petBodyIntensity + energy + 0.07f);
        }

        petStrokeAccum_ += delta;
        if (!isCurrentlyPetting_ && petStrokeAccum_ > 45.0f) {
            isCurrentlyPetting_ = true;
            totalPetSessions++;
        }

        float dx = (canvasPoint.x - SeatAnchor.x) / 60.0f;
        headTilt.target = std::clamp(dx * 0.16f, -0.18f, 0.18f);
        headOffsetY.velocity += 18.0f;
    }

    void step(float rawDt, const RECT& windowRect, InputEngine& engine, const CatSettings& settings) {
        float dt = std::min(rawDt, 1.0f / 25.0f);
        time += dt;
        engine.pollMouse(dt);

        double now = nowSeconds();
        const auto& activeKeys = engine.activeKeys;
        const auto& orderedKeys = engine.pressedOrder;

        // Snapshot the analyser once per frame; renderer reads this same state.
        {
            auto s = MusicPulse::instance().snapshot();
            pulse.level = s.level;
            pulse.bass = s.bass;
            pulse.beat = s.beat;
            pulse.playing = s.playing;
            for (int i = 0; i < MusicPulse::BandCount; ++i) {
                pulse.bands[i] = s.bands[i];
                pulse.peaks[i] = s.peaks[i];
            }
        }

        // 2a. Fast-typing overload state machine.
        // 1.8s window + sustained-fast gate: casual typing never reaches the
        // straining face; only a real >8 keys/s burst held ~0.85s builds strain.
        keyTimes_.erase(std::remove_if(keyTimes_.begin(), keyTimes_.end(),
                                       [now](double t) { return now - t > 1.8; }), keyTimes_.end());
        double rate = (double)keyTimes_.size() / 1.8;
        bool activelyTyping = engine.lastKeyActivityTime > 0.0 && (now - engine.lastKeyActivityTime) < 0.35;
        bool fastEnough = activelyTyping && rate >= 8.0;
        if (fastEnough) {
            if (fastStreakStart_ == 0.0) fastStreakStart_ = now;
        } else {
            fastStreakStart_ = 0.0;
        }
        bool sustainedFast = fastEnough && (now - fastStreakStart_) >= 0.85;
        double normalized = std::clamp((rate - 7.0) / 5.0, 0.0, 1.0);
        float strainTarget = sustainedFast ? (float)std::pow(normalized, 1.4) : 0.0f;
        float strainRate = strainTarget > strain ? 5.5f : 3.2f;
        strain += (strainTarget - strain) * std::min(1.0f, dt * strainRate);

        bool fastTyping = sustainedFast && rate >= 10.0 && (now - engine.lastKeyActivityTime) < 0.12;
        if (fastTyping) {
            lastFastKeyTime_ = now;
            overloadArmed_ = true;
        }
        if (isFried) {
            friedTimeLeft -= dt;
            float moveSpeed = std::hypot(engine.mouseVelocity.x, engine.mouseVelocity.y);
            if (friedTimeLeft <= 0.0f || (moveSpeed > 55.0f && now - engine.lastMouseMoveTime < 0.25)) {
                endFried(now);
            }
        } else {
            double noKeyFor = engine.lastKeyActivityTime > 0.0 ? (now - engine.lastKeyActivityTime) : 1e9;
            double sinceFast = lastFastKeyTime_ > 0.0 ? (now - lastFastKeyTime_) : 1e9;
            if (overloadArmed_ && noKeyFor > 0.16 && sinceFast > 0.12 && sinceFast < 0.85) {
                startFried(now);
            }
            if (sinceFast > 2.5) overloadArmed_ = false;
        }

        // 1. Petting decay & sparkles
        if (now - lastPetTime_ > 0.28) {
            petHeadIntensity = std::max(0.0f, petHeadIntensity - dt * 1.4f);
            petBodyIntensity = std::max(0.0f, petBodyIntensity - dt * 1.2f);
            if (petHeadIntensity < 0.05f && petBodyIntensity < 0.05f) {
                isCurrentlyPetting_ = false;
                petStrokeAccum_ = 0.0f;
            }
        } else if (petHeadIntensity > 0.55f || petBodyIntensity > 0.55f) {
            petSparkleCooldown_ -= dt;
            if (petSparkleCooldown_ <= 0.0f) {
                petSparkleCooldown_ = 0.42f;
                sparkles.push_back({
                    { SeatAnchor.x + randRange(-44.0f, 44.0f), 88.0f + randRange(-14.0f, 18.0f) },
                    { randRange(-10.0f, 10.0f), -24.0f },
                    0.0f, 0.9f, false
                });
            }
        }

        // 2. Sleepy idle detection
        double lastAny = std::max(engine.lastKeyActivityTime, std::max(engine.lastMouseMoveTime, lastPetTime_));
        double idleSec = lastAny > 0.0 ? (now - lastAny) : 0.0;
        if (activeKeys.empty() && idleSec > 45.0) {
            float targetSleep = std::min(1.0f, (float)((idleSec - 45.0) / 35.0));
            sleepiness += (targetSleep - sleepiness) * dt * 1.5f;
            if (sleepiness > 0.8f) {
                sleepZCooldown_ -= dt;
                if (sleepZCooldown_ <= 0.0f) {
                    sleepZCooldown_ = 2.6f;
                    sparkles.push_back({ { SeatAnchor.x + 42.0f, 100.0f }, { 12.0f, -18.0f }, 0.0f, 1.1f, true });
                }
            }
        } else {
            sleepiness = std::max(0.0f, sleepiness - dt * 5.0f);
        }

        // 2b. Fast Mouse Movement -> Hunting Mode (big round boba pupils + low crouch!)
        float mouseSpeed = std::hypot(engine.mouseVelocity.x, engine.mouseVelocity.y);
        if (mouseSpeed > 460.0f && petHeadIntensity < 0.25f && petBodyIntensity < 0.25f) {
            float boost = std::min(1.0f, (mouseSpeed - 460.0f) / 1100.0f);
            huntIntensity.target = std::min(1.0f, huntIntensity.target + (0.45f + boost * 1.15f) * dt);
            sleepiness = 0.0f;
        } else {
            huntIntensity.target = std::max(0.0f, huntIntensity.target - dt * 0.65f);
        }
        huntIntensity.step(dt, 85.0f, 16.0f);
        float hunt = std::clamp(huntIntensity.value, 0.0f, 1.0f);

        // 3. Limb assignment (Left Paw, Right Paw, 3-Key Hind Foot!)
        constexpr double tapHoldWindow = 0.14;
        bool mouseRecent = (now - engine.lastMouseMoveTime < 2.2) || engine.leftMouseDown || engine.rightMouseDown;
        bool mouseActivelyUsed = (now - engine.lastMouseMoveTime < 0.75) || engine.leftMouseDown || engine.rightMouseDown;

        std::vector<PhysicalKey> leftCands, rightCands;
        for (PhysicalKey k : orderedKeys) {
            if (prefersViewerLeftPaw(k)) leftCands.push_back(k);
            else rightCands.push_back(k);
        }

        PhysicalKey leftKey = leftCands.empty() ? PhysicalKey::None : leftCands.back();
        PhysicalKey rightKey = rightCands.empty() ? PhysicalKey::None : rightCands.back();
        PhysicalKey footKey = PhysicalKey::None;

        if (leftKey == PhysicalKey::None && rightCands.size() >= 2 && !mouseActivelyUsed) {
            auto sorted = rightCands;
            std::sort(sorted.begin(), sorted.end(), [](PhysicalKey a, PhysicalKey b) {
                return KeyboardLayout::canvasPointForKey(a).x < KeyboardLayout::canvasPointForKey(b).x;
            });
            leftKey = sorted.front();
            rightKey = sorted.back();
        } else if (rightKey == PhysicalKey::None && leftCands.size() >= 2) {
            auto sorted = leftCands;
            std::sort(sorted.begin(), sorted.end(), [](PhysicalKey a, PhysicalKey b) {
                return KeyboardLayout::canvasPointForKey(a).x < KeyboardLayout::canvasPointForKey(b).x;
            });
            leftKey = sorted.front();
            rightKey = sorted.back();
        }

        if (settings.footEasterEgg) {
            if (orderedKeys.size() >= 3) {
                for (PhysicalKey k : orderedKeys) {
                    if (k != leftKey && k != rightKey) { footKey = k; break; }
                }
            } else if (mouseActivelyUsed && leftKey == PhysicalKey::None && rightCands.size() >= 2) {
                for (PhysicalKey k : rightCands) {
                    if (k != rightKey) { footKey = k; break; }
                }
            }
        }

        if (leftKey == PhysicalKey::None && recentLeftKey_ != PhysicalKey::None && now - recentLeftTime_ < tapHoldWindow) {
            leftKey = recentLeftKey_;
        }
        if (rightKey == PhysicalKey::None && recentRightKey_ != PhysicalKey::None && now - recentRightTime_ < tapHoldWindow) {
            rightKey = recentRightKey_;
        }

        // Music groove affects only head/ears/tail — paws keep their normal
        // typing and mouse behaviour (matches the macOS implementation).
        bool musicGrooveActive = settings.musicMode && pulse.playing &&
            leftKey == PhysicalKey::None && rightKey == PhysicalKey::None &&
            !mouseRecent && sleepiness < 0.3f;

        // Subtle mini-mouse movement
        mouseOffset.setTarget({
            std::clamp(engine.mouseVelocity.x * 0.0045f, -5.5f, 5.5f),
            std::clamp(engine.mouseVelocity.y * 0.0045f, -4.5f, 4.5f)
        });
        mouseOffset.step(dt, 120.0f, 16.0f);
        mousePressLeft.step(dt, 400.0f, 24.0f);
        mousePressRight.step(dt, 400.0f, 24.0f);

        Pt liveMouse = { MouseBaseCenter.x + mouseOffset.point().x, MouseBaseCenter.y + mouseOffset.point().y };

        if (leftKey != PhysicalKey::None) {
            leftPaw.setTarget(KeyboardLayout::canvasPointForKey(leftKey));
            leftPawTyping = true;
            leftPawOnMouse = false;
        } else if (mouseRecent && sleepiness < 0.3f) {
            leftPaw.setTarget({ liveMouse.x + 2.0f, liveMouse.y - 3.0f });
            leftPawTyping = false;
            leftPawOnMouse = true;
        } else {
            leftPaw.setTarget(LeftPawRest);
            leftPawTyping = false;
            leftPawOnMouse = false;
        }

        if (rightKey != PhysicalKey::None) {
            rightPaw.setTarget(KeyboardLayout::canvasPointForKey(rightKey));
            rightPawTyping = true;
        } else {
            rightPaw.setTarget(RightPawRest);
            rightPawTyping = false;
        }

        if (footKey != PhysicalKey::None) {
            hindFoot.setTarget(KeyboardLayout::canvasPointForKey(footKey));
            hindFootActive.target = 1.0f;
        } else {
            hindFoot.setTarget(HindFootRest);
            hindFootActive.target = 0.0f;
        }

        leftPaw.step(dt, 360.0f, 24.0f);
        rightPaw.step(dt, 360.0f, 24.0f);
        hindFoot.step(dt, 320.0f, 22.0f);
        hindFootActive.step(dt, 260.0f, 22.0f);

        // 4. Body lean, squash & ear motion
        float targetShiftX = 0.0f, targetBodyTilt = 0.0f;
        if (leftPawOnMouse && !rightPawTyping) {
            targetShiftX = -10.0f;
            targetBodyTilt = -0.075f;
        } else if (leftPawOnMouse && rightPawTyping) {
            targetShiftX = -3.0f;
            targetBodyTilt = (rightPaw.point().x - 196.0f) * 0.0008f;
        } else if (leftPawTyping || rightPawTyping) {
            float avgX = ((leftPawTyping ? leftPaw.point().x : 184.0f) + (rightPawTyping ? rightPaw.point().x : 184.0f)) * 0.5f;
            targetShiftX = (avgX - 184.0f) * 0.14f;
            targetBodyTilt = (avgX - 184.0f) * 0.0011f;
        }
        bodyShiftX.target = std::clamp(targetShiftX, -16.0f, 16.0f);
        bodyTilt.target = std::clamp(targetBodyTilt, -0.12f, 0.12f);
        bodySquash.target = 1.0f - hunt * 0.11f;
        headOffsetY.target = (leftPawTyping || rightPawTyping) ? 3.5f : (sleepiness * 5.0f + hunt * 10.5f);
        earFold.target = std::max(petHeadIntensity * 0.7f, petBodyIntensity * 0.45f) + sleepiness * 0.25f - hunt * 0.18f;
        earTwitch.target = 0.0f;

        // Overload posture: tense crouch while straining, drooping deflation when fried.
        if (isStraining()) {
            earTwitch.target = std::sin((float)now * 26.0f) * strain * 1.5f;
            headOffsetY.target += strain * 2.0f;
        }
        if (isFried) {
            float droop = std::min(1.0f, (3.0f - friedTimeLeft) * 2.5f);
            headOffsetY.target += 7.0f * droop;
            earFold.target = std::max(earFold.target, 0.75f * droop);
            bodySquash.target = 1.0f - 0.07f * droop;
        }
        if (musicGrooveActive) {
            earTwitch.target = std::sin((float)now * 3.2f) * (0.6f + (float)pulse.level * 2.2f)
                             + (float)pulse.beat * 3.0f;
        }

        bodyShiftX.step(dt, 140.0f, 18.0f);
        bodyTilt.step(dt, 140.0f, 18.0f);
        bodySquash.step(dt, 280.0f, 18.0f);
        headOffsetY.step(dt, 180.0f, 19.0f);
        earFold.step(dt, 120.0f, 16.0f);
        earTwitch.step(dt, 320.0f, 16.0f);

        // 5. 2.5D Head Turning (Yaw + Pitch) & Eye Tracking (Windows screen Y is top-down!)
        bool typingRecently = !activeKeys.empty() || (now - engine.lastKeyActivityTime < 0.65);
        bool mouseMovedRecently = (now - engine.lastMouseMoveTime < 1.2);
        Pt eyeOrigin = { SeatAnchor.x + bodyShiftX.value, 124.0f + headOffsetY.value };

        float winW = std::max(1.0f, (float)(windowRect.right - windowRect.left));
        float winScale = std::max(0.2f, winW / CanvasWidth);
        float headScreenX = (float)windowRect.left + eyeOrigin.x * winScale;
        float headScreenY = (float)windowRect.top  + eyeOrigin.y * winScale;

        float curDx = ((float)engine.lastCursorPos.x - headScreenX) / 290.0f;
        float curDy = ((float)engine.lastCursorPos.y - headScreenY) / 260.0f;
        float curMag = std::hypot(curDx, curDy);
        float clampedCur = std::min(1.0f, curMag);
        float cursorNX = curMag > 0.001f ? (curDx / curMag) * clampedCur : 0.0f;
        float cursorNY = curMag > 0.001f ? (curDy / curMag) * clampedCur : 0.0f;

        float lookX = cursorNX, lookY = cursorNY;
        if (typingRecently && !mouseMovedRecently && hasLastTypedPoint_) {
            lookX = std::clamp((lastTypedPoint_.x - eyeOrigin.x) / 95.0f, -0.85f, 0.85f);
            lookY = std::clamp((lastTypedPoint_.y - eyeOrigin.y) / 125.0f, -0.3f, 0.92f);
        } else if (typingRecently && mouseMovedRecently && hasLastTypedPoint_) {
            float kdx = std::clamp((lastTypedPoint_.x - eyeOrigin.x) / 95.0f, -0.85f, 0.85f);
            lookX = cursorNX * 0.72f + kdx * 0.28f;
            lookY = cursorNY * 0.72f + 0.25f;
        }

        if (sleepiness > 0.45f) {
            headYaw.target = 0.0f;
            headPitch.target = 0.45f * sleepiness;
        } else {
            headYaw.target = std::clamp(lookX, -1.0f, 1.0f);
            headPitch.target = std::clamp(lookY, -1.0f, 1.0f);
        }
        if (musicGrooveActive) {
            headPitch.target += (float)pulse.beat * 0.16f + (float)pulse.level * 0.04f;
        }
        if (isFried) {
            float droop = std::min(1.0f, (3.0f - friedTimeLeft) * 2.5f);
            headPitch.target = 0.32f * droop;
            headYaw.target *= (1.0f - 0.6f * droop);
        }
        float headStiff = 88.0f + hunt * 75.0f;
        float headDamp  = 14.5f + hunt * 4.5f;
        headYaw.step(dt, headStiff, headDamp);
        headPitch.step(dt, headStiff, headDamp);

        if (now - lastPetTime_ > 0.28) {
            headTilt.target = bodyTilt.target * 0.45f + headYaw.value * (0.11f + hunt * 0.05f) - headYaw.value * headPitch.value * 0.04f;
        }
        if (musicGrooveActive) {
            headTilt.target += std::sin((float)now * 1.9f) * (float)pulse.level * 0.16f
                             + (float)pulse.beat * 0.12f;
        }
        headTilt.step(dt, 130.0f, 16.0f);

        eyeGaze.setTarget({ lookX * 0.88f, lookY * 0.85f });
        eyeGaze.step(dt, 210.0f + hunt * 80.0f, 21.0f);

        if (hindFootActive.value > 0.3f) {
            pupilScale.target = 1.24f;
        } else if (now - engine.lastKeyActivityTime > 0.45 && now - engine.lastMouseClickTime > 0.45) {
            pupilScale.target = 1.0f;
        }
        pupilScale.step(dt, 150.0f, 18.0f);

        // 6. Blinking (no blinking during locked-on hunting!)
        if (isBlinking_) {
            blinkTimer_ += dt;
            constexpr float blinkDur = 0.14f;
            if (blinkTimer_ >= blinkDur) {
                isBlinking_ = false;
                blinkProgress_ = 0.0f;
                nextBlinkTime_ = time + randRange(2.6f, 5.6f);
            } else {
                blinkProgress_ = std::sin((blinkTimer_ / blinkDur) * 3.14159265f);
            }
        } else if (time >= nextBlinkTime_ && sleepiness < 0.5f && petHeadIntensity < 0.3f && hunt < 0.35f) {
            isBlinking_ = true;
            blinkTimer_ = 0.0f;
        }

        // 7. Tail wag speed
        float kpmBoost = std::min(2.4f, (float)engine.currentKPM() / 160.0f);
        float petBoost = std::max(petHeadIntensity, petBodyIntensity) * 1.4f;
        float musicBoost = (settings.musicMode && pulse.playing)
            ? (float)pulse.level * 2.2f + (float)pulse.beat * 1.5f : 0.0f;
        float tailSpeed = 1.85f + kpmBoost + petBoost + hunt * 2.8f + musicBoost - sleepiness * 1.1f;
        tailPhase += dt * tailSpeed;

        // 8. Keycap glow decay
        std::unordered_set<PhysicalKey> visualActive;
        for (PhysicalKey k : activeKeys) visualActive.insert(visualKeyOf(k));
        for (auto it = keyGlow.begin(); it != keyGlow.end(); ) {
            if (visualActive.count(it->first)) {
                it->second = 1.0f;
                ++it;
            } else {
                it->second -= dt * 4.5f;
                if (it->second <= 0.01f) it = keyGlow.erase(it);
                else ++it;
            }
        }
        for (PhysicalKey vk : visualActive) keyGlow[vk] = 1.0f;

        // 9. Floating keycaps
        for (int i = (int)floatingKeycaps.size() - 1; i >= 0; --i) {
            auto& b = floatingKeycaps[i];
            b.age += dt;
            b.position.x += b.velocity.x * dt;
            b.position.y += b.velocity.y * dt;
            b.velocity.x *= (1.0f - dt * 2.4f);
            b.velocity.y *= (1.0f - dt * 1.6f);
            if (b.age >= b.lifetime) floatingKeycaps.erase(floatingKeycaps.begin() + i);
        }

        // 10. Sparkles / Sleep Z
        for (int i = (int)sparkles.size() - 1; i >= 0; --i) {
            auto& sp = sparkles[i];
            sp.age += dt;
            sp.position.x += sp.velocity.x * dt;
            sp.position.y += sp.velocity.y * dt;
            if (sp.age >= sp.lifetime) sparkles.erase(sparkles.begin() + i);
        }

        // 10b. Overload smoke wisps — keep emitting while fried, then drift away.
        if (isFried) {
            smokeCooldown_ -= dt;
            if (smokeCooldown_ <= 0.0f) {
                smokeCooldown_ = 0.14f;
                spawnSmoke(SeatAnchor.x + bodyShiftX.value);
            }
        }
        for (int i = (int)smokePuffs.size() - 1; i >= 0; --i) {
            auto& puff = smokePuffs[i];
            puff.age += dt;
            puff.position.x += puff.velocity.x * dt
                + std::sin(puff.age * 2.6f + puff.seed) * 7.0f * dt;
            puff.position.y += puff.velocity.y * dt;
            if (puff.age >= puff.lifetime) smokePuffs.erase(smokePuffs.begin() + i);
        }

        // 11. Music overlay: spectrum presence, head bob, beat squint and notes.
        const bool musicActive = settings.musicMode && pulse.playing && !isFried;
        float presenceTarget = musicActive ? 1.0f : 0.0f;
        equalizerPresence += (presenceTarget - equalizerPresence) * std::min(1.0f, dt * 5.0f);
        if (musicActive) {
            float bobTarget = (float)pulse.bass * 8.0f + (float)pulse.beat * 11.0f;
            musicBounce += (bobTarget - musicBounce) * std::min(1.0f, dt * 18.0f);
            musicBounce *= (1.0f - dt * 2.2f);
            if (pulse.beat > 0.4) musicBlinkBoost = 0.95f;
            musicBlinkBoost = std::max(0.0f, musicBlinkBoost - dt * 2.2f);
            if ((pulse.beat > 0.4 && now - lastNoteTime_ > 0.16)
                || (pulse.level > 0.18 && now - lastNoteTime_ > 0.34)) {
                spawnMusicNote(now);
                lastNoteTime_ = now;
            }
        } else {
            musicBounce *= (1.0f - dt * 6.0f);
            musicBlinkBoost = std::max(0.0f, musicBlinkBoost - dt * 3.0f);
        }
        for (int i = (int)musicNotes.size() - 1; i >= 0; --i) {
            auto& note = musicNotes[i];
            note.age += dt;
            note.position.x += note.velocity.x * dt;
            note.position.y += note.velocity.y * dt;
            note.velocity.y -= 7.0f * dt;
            if (note.age >= note.lifetime) musicNotes.erase(musicNotes.begin() + i);
        }
    }

private:
    float nextBlinkTime_ = 3.2f;
    float blinkProgress_ = 0.0f;
    bool isBlinking_ = false;
    float blinkTimer_ = 0.0f;

    float petStrokeAccum_ = 0.0f;
    double lastPetTime_ = 0.0;
    bool isCurrentlyPetting_ = false;
    float petSparkleCooldown_ = 0.0f;
    float sleepZCooldown_ = 0.0f;

    PhysicalKey recentLeftKey_ = PhysicalKey::None;
    double recentLeftTime_ = 0.0;
    PhysicalKey recentRightKey_ = PhysicalKey::None;
    double recentRightTime_ = 0.0;
    bool hasLastTypedPoint_ = false;
    Pt lastTypedPoint_ = { 184.0f, 260.0f };

    int badgeCascade_ = 0;
    double lastBadgeTime_ = 0.0;

    // Overload state
    std::vector<double> keyTimes_;
    double fastStreakStart_ = 0.0;
    double lastFastKeyTime_ = 0.0;
    bool overloadArmed_ = false;
    float smokeCooldown_ = 0.0f;

    // Music overlay particle timing
    double lastNoteTime_ = 0.0;
    int noteGlyphIndex_ = 0;

    void startFried(double now) {
        isFried = true;
        friedTimeLeft = 3.0f;
        strain = 0.0f;
        smokeCooldown_ = 0.0f;
        keyTimes_.clear();
        fastStreakStart_ = 0.0;
        lastFastKeyTime_ = 0.0;
        overloadArmed_ = false;
        for (int i = 0; i < 3; ++i) spawnSmoke(SeatAnchor.x + bodyShiftX.value, true);
        musicNotes.clear();
        (void)now;
    }

    void endFried(double /*now*/) {
        isFried = false;
        friedTimeLeft = 0.0f;
        lastFastKeyTime_ = 0.0;
        overloadArmed_ = false;
        keyTimes_.clear();
        fastStreakStart_ = 0.0;
        strain = 0.0f;
        smokeCooldown_ = 0.0f;
    }

    void spawnSmoke(float seatX, bool strong = false) {
        float spread = strong ? 20.0f : 16.0f;
        smokePuffs.push_back({
            { seatX + randRange(-spread, spread), 92.0f + randRange(-8.0f, 6.0f) },
            { randRange(-7.0f, 7.0f), -(strong ? randRange(30.0f, 46.0f) : randRange(22.0f, 38.0f)) },
            randRange(0.18f, 0.5f),
            randRange(1.0f, 1.7f),
            randRange(6.0f, 11.0f),
            randRange(0.0f, 6.28f)
        });
        if (smokePuffs.size() > 26) {
            smokePuffs.erase(smokePuffs.begin(), smokePuffs.end() - 26);
        }
    }

    void spawnMusicNote(double /*now*/) {
        float headX = SeatAnchor.x + bodyShiftX.value;
        noteGlyphIndex_ = (noteGlyphIndex_ + 1) % 4;
        musicNotes.push_back({
            { headX + randRange(-54.0f, 54.0f), 102.0f + randRange(-12.0f, 12.0f) },
            { randRange(-16.0f, 16.0f),
              -44.0f - (float)pulse.level * 26.0f - randRange(0.0f, 18.0f) },
            0.0f,
            randRange(1.2f, 1.8f),
            noteGlyphIndex_,
            randRange(-0.28f, 0.28f),
            randRange(1.0f, 1.5f) * (1.0f + (float)pulse.beat * 0.25f)
        });
        if (musicNotes.size() > 20) {
            musicNotes.erase(musicNotes.begin(), musicNotes.end() - 20);
        }
    }

    static float randRange(float a, float b) {
        static thread_local std::mt19937 rng{ std::random_device{}() };
        std::uniform_real_distribution<float> dist(a, b);
        return dist(rng);
    }

    void spawnFloatingKeycap(const std::wstring& label, Pt pt, double now) {
        if (label.empty()) return;
        if (now - lastBadgeTime_ < 0.38) badgeCascade_ = (badgeCascade_ + 1) % 6;
        else badgeCascade_ = 0;
        lastBadgeTime_ = now;

        static const float spread[6] = { -10.0f, 14.0f, -22.0f, 26.0f, 2.0f, 36.0f };
        float dx = spread[badgeCascade_] + randRange(-3.0f, 3.0f);
        float startX = std::clamp(pt.x + dx * 0.45f, 55.0f, 315.0f);
        float startY = pt.y - 26.0f - (float)(badgeCascade_ % 2) * 8.0f;

        floatingKeycaps.push_back({
            label,
            { startX, startY },
            { dx * 0.65f, -36.0f - randRange(0.0f, 14.0f) },
            0.0f, 1.25f, randRange(-0.07f, 0.07f)
        });
        if (floatingKeycaps.size() > 16) {
            floatingKeycaps.erase(floatingKeycaps.begin(), floatingKeycaps.begin() + (floatingKeycaps.size() - 16));
        }
    }
};

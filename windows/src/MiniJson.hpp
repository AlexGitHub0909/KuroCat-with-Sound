#pragma once

// Tiny read-only JSON parser, sufficient for KuroCat's SoundThemes manifests.
// It intentionally supports only the shapes used by catalog.json / theme.json:
// objects, arrays, strings, numbers, booleans and null. No dependencies.

#include <cstdint>
#include <cstdlib>
#include <map>
#include <string>
#include <vector>

namespace MiniJson {

struct Value {
    enum class Type { Null, Bool, Number, String, Array, Object };

    Type type = Type::Null;
    bool boolean = false;
    double number = 0.0;
    std::string text;
    std::vector<Value> array;
    std::map<std::string, Value> object;

    bool isString() const { return type == Type::String; }
    bool isArray() const { return type == Type::Array; }
    bool isObject() const { return type == Type::Object; }

    const Value* find(const std::string& key) const {
        if (type != Type::Object) return nullptr;
        auto it = object.find(key);
        return it == object.end() ? nullptr : &it->second;
    }

    std::string stringOr(const std::string& fallback) const {
        return isString() ? text : fallback;
    }
};

class Parser {
public:
    explicit Parser(const std::string& input) : s_(input) {}

    bool parse(Value& out) {
        skipWs();
        if (!parseValue(out)) return false;
        skipWs();
        return pos_ == s_.size();
    }

private:
    const std::string& s_;
    size_t pos_ = 0;

    void skipWs() {
        while (pos_ < s_.size()) {
            char c = s_[pos_];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') ++pos_;
            else break;
        }
    }

    bool consume(char c) {
        if (pos_ < s_.size() && s_[pos_] == c) { ++pos_; return true; }
        return false;
    }

    static void appendUtf8(std::string& out, uint32_t cp) {
        if (cp <= 0x7F) {
            out.push_back((char)cp);
        } else if (cp <= 0x7FF) {
            out.push_back((char)(0xC0 | (cp >> 6)));
            out.push_back((char)(0x80 | (cp & 0x3F)));
        } else if (cp <= 0xFFFF) {
            out.push_back((char)(0xE0 | (cp >> 12)));
            out.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back((char)(0x80 | (cp & 0x3F)));
        } else {
            out.push_back((char)(0xF0 | (cp >> 18)));
            out.push_back((char)(0x80 | ((cp >> 12) & 0x3F)));
            out.push_back((char)(0x80 | ((cp >> 6) & 0x3F)));
            out.push_back((char)(0x80 | (cp & 0x3F)));
        }
    }

    bool hex4(uint32_t& value) {
        if (pos_ + 4 > s_.size()) return false;
        value = 0;
        for (int i = 0; i < 4; ++i) {
            char c = s_[pos_++];
            uint32_t d;
            if (c >= '0' && c <= '9') d = (uint32_t)(c - '0');
            else if (c >= 'a' && c <= 'f') d = (uint32_t)(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') d = (uint32_t)(c - 'A' + 10);
            else return false;
            value = (value << 4) | d;
        }
        return true;
    }

    bool parseString(std::string& out) {
        if (!consume('"')) return false;
        out.clear();
        while (pos_ < s_.size()) {
            unsigned char c = (unsigned char)s_[pos_++];
            if (c == '"') return true;
            if (c == '\\') {
                if (pos_ >= s_.size()) return false;
                char e = s_[pos_++];
                switch (e) {
                    case '"': out.push_back('"'); break;
                    case '\\': out.push_back('\\'); break;
                    case '/': out.push_back('/'); break;
                    case 'b': out.push_back('\b'); break;
                    case 'f': out.push_back('\f'); break;
                    case 'n': out.push_back('\n'); break;
                    case 'r': out.push_back('\r'); break;
                    case 't': out.push_back('\t'); break;
                    case 'u': {
                        uint32_t cp = 0;
                        if (!hex4(cp)) return false;
                        // Combine UTF-16 surrogate pairs when present.
                        if (cp >= 0xD800 && cp <= 0xDBFF && pos_ + 6 <= s_.size() &&
                            s_[pos_] == '\\' && s_[pos_ + 1] == 'u') {
                            pos_ += 2;
                            uint32_t low = 0;
                            if (!hex4(low) || low < 0xDC00 || low > 0xDFFF) return false;
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
                        }
                        appendUtf8(out, cp);
                        break;
                    }
                    default: return false;
                }
            } else {
                out.push_back((char)c);
            }
        }
        return false;
    }

    bool parseValue(Value& out) {
        skipWs();
        if (pos_ >= s_.size()) return false;
        char c = s_[pos_];
        if (c == '"') {
            std::string text;
            if (!parseString(text)) return false;
            out.type = Value::Type::String;
            out.text = text;
            return true;
        }
        if (c == '{') {
            ++pos_;
            out.type = Value::Type::Object;
            out.object.clear();
            skipWs();
            if (consume('}')) return true;
            while (pos_ < s_.size()) {
                std::string key;
                if (!parseString(key)) return false;
                skipWs();
                if (!consume(':')) return false;
                Value child;
                if (!parseValue(child)) return false;
                out.object[key] = child;
                skipWs();
                if (consume('}')) return true;
                if (!consume(',')) return false;
                skipWs();
            }
            return false;
        }
        if (c == '[') {
            ++pos_;
            out.type = Value::Type::Array;
            out.array.clear();
            skipWs();
            if (consume(']')) return true;
            while (pos_ < s_.size()) {
                Value child;
                if (!parseValue(child)) return false;
                out.array.push_back(child);
                skipWs();
                if (consume(']')) return true;
                if (!consume(',')) return false;
                skipWs();
            }
            return false;
        }
        if (c == 't' && s_.compare(pos_, 4, "true") == 0) {
            pos_ += 4; out.type = Value::Type::Bool; out.boolean = true; return true;
        }
        if (c == 'f' && s_.compare(pos_, 5, "false") == 0) {
            pos_ += 5; out.type = Value::Type::Bool; out.boolean = false; return true;
        }
        if (c == 'n' && s_.compare(pos_, 4, "null") == 0) {
            pos_ += 4; out.type = Value::Type::Null; return true;
        }
        if (c == '-' || (c >= '0' && c <= '9')) {
            size_t start = pos_;
            if (s_[pos_] == '-') ++pos_;
            while (pos_ < s_.size() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
            if (pos_ < s_.size() && s_[pos_] == '.') {
                ++pos_;
                while (pos_ < s_.size() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
            }
            if (pos_ < s_.size() && (s_[pos_] == 'e' || s_[pos_] == 'E')) {
                ++pos_;
                if (pos_ < s_.size() && (s_[pos_] == '+' || s_[pos_] == '-')) ++pos_;
                while (pos_ < s_.size() && s_[pos_] >= '0' && s_[pos_] <= '9') ++pos_;
            }
            out.type = Value::Type::Number;
            out.number = std::strtod(s_.substr(start, pos_ - start).c_str(), nullptr);
            return true;
        }
        return false;
    }
};

inline bool parse(const std::string& text, Value& out) {
    Parser p(text);
    return p.parse(out);
}

} // namespace MiniJson

/*
 * Copyright (c) 2025 Huawei Technologies Co.,Ltd.
 *
 * Note: Provides interface for openGauss as tokenizer by using cppjieba api.
 *
 * tokenizer.cpp
 *
 * IDENTIFICATION
 *        contrib/jieba_tokenizer/tokenizer.cpp
 *
 * -------------------------------------------------------------------------
 */
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <mutex>
#include <unordered_map>
#include <cerrno>
#include <securec.h>
#include "zlib.h"
#include "cppjieba/Jieba.hpp"
#include "tokenizer.h"

#ifndef PATH_MAX
#define PATH_MAX 4096
#endif

const size_t MAX_LENGTH_CRC = 100;
const size_t MAX_KEYWORD_NUM = 100000;

const char* const DICT_PATH = "lib/jieba_dict/jieba.dict.utf8";
const char* const HMM_PATH = "lib/jieba_dict/hmm_model.utf8";
const char* const USER_DICT_PATH = "lib/jieba_dict/user.dict.utf8";
const char* const IDF_PATH = "lib/jieba_dict/idf.utf8";
const char* const STOP_WORD_PATH = "lib/jieba_dict/stop_words.utf8";

/* File names relative to dict base directory */
static const char* const DICT_FILES[] = {
    "jieba.dict.utf8", "hmm_model.utf8", "user.dict.utf8", "idf.utf8", "stop_words.utf8"
};

static std::unordered_map<std::string, std::unique_ptr<cppjieba::Jieba>> g_tokenizerCache;
static std::mutex g_tokenizerMutex;

inline static bool IsWhitespace(const std::string& str)
{
    return std::all_of(str.begin(), str.end(), ::isspace);
}

inline static std::string Convert2LowerCase(const std::string& str)
{
    std::string result = str;
    std::transform(result.begin(), result.end(), result.begin(), [](unsigned char c) {
        return std::tolower(c);
    });
    return result;
}

inline static uint32_t HashString2Uint32(const std::string& srcStr)
{
    std::string subStr = srcStr;
    if (srcStr.length() > MAX_LENGTH_CRC) {
        subStr = srcStr.substr(0, MAX_LENGTH_CRC);
    }

    uint32_t crc = crc32(0, Z_NULL, 0);
    crc = crc32(crc, reinterpret_cast<const Bytef*>(subStr.data()), subStr.length());
    return crc;
}

static void ConvertEmbeddingMap(std::unordered_map<std::string, std::pair<uint32_t, float>> tokensMap,
    EmbeddingMap *embeddingMap)
{
    embeddingMap->size = tokensMap.size();
    if  (embeddingMap->size == 0) {
        return;
    }
    embeddingMap->tokens = (EmbeddingTokenInfo *)malloc(embeddingMap->size * sizeof(EmbeddingTokenInfo));
    if (embeddingMap->tokens == nullptr) {
        embeddingMap->size = 0;
        return;
    }

    size_t idx = 0;
    for (const auto& token : tokensMap) {
        embeddingMap->tokens[idx].key = token.second.first;
        embeddingMap->tokens[idx].value = token.second.second;
        errno_t rc = strncpy_s(embeddingMap->tokens[idx].token, MAX_TOKEN_LEN, token.first.c_str(), MAX_TOKEN_LEN - 1);
        if (rc != EOK) {
            free(embeddingMap->tokens);
            embeddingMap->tokens = nullptr;
            embeddingMap->size = 0;
            return;
        }
        idx++;
    }
}

/* Create Jieba instance from base directory (must contain the 5 dict files) */
static cppjieba::Jieba* CreateJiebaFromBaseDir(const std::string& baseDir)
{
    std::string dictPath = baseDir + "/" + DICT_FILES[0];
    std::string hmmPath = baseDir + "/" + DICT_FILES[1];
    std::string userDictPath = baseDir + "/" + DICT_FILES[2];
    std::string idfPath = baseDir + "/" + DICT_FILES[3];
    std::string stopWordPath = baseDir + "/" + DICT_FILES[4];
    return new cppjieba::Jieba(dictPath, hmmPath, userDictPath, idfPath, stopWordPath);
}

/* Get default dict base path (GAUSSHOME/lib/jieba_dict), resolved. Returns empty on failure. */
static std::string GetDefaultDictBasePath()
{
    char* installPath = getenv("GAUSSHOME");
    if (installPath == nullptr) {
        return "";
    }
    char path[PATH_MAX + 1] = {0};
    const char* baseDir = installPath;
    if (realpath(installPath, path) != nullptr) {
        baseDir = path;
    }
    char basePath[PATH_MAX + 1] = {0};
    int ret = snprintf_s(basePath, PATH_MAX + 1, PATH_MAX, "%s/lib/jieba_dict", baseDir);
    if (ret < 0) {
        return "";
    }
    char resolved[PATH_MAX + 1] = {0};
    if (realpath(basePath, resolved) == nullptr) {
        return std::string(basePath);  /* fallback to unresolved if realpath fails */
    }
    return std::string(resolved);
}

#ifdef __cplusplus
extern "C" {
#endif

void* GetOrCreateTokenizer(const char* dictBasePath)
{
    std::string cacheKey;
    if (dictBasePath == nullptr || dictBasePath[0] == '\0') {
        cacheKey = GetDefaultDictBasePath();
        if (cacheKey.empty()) {
            return nullptr;
        }
    } else {
        cacheKey = dictBasePath;
    }

    std::lock_guard<std::mutex> lock(g_tokenizerMutex);
    auto it = g_tokenizerCache.find(cacheKey);
    if (it != g_tokenizerCache.end()) {
        return it->second.get();
    }
    cppjieba::Jieba* jieba = nullptr;
    try {
        jieba = CreateJiebaFromBaseDir(cacheKey);
    } catch (...) {
        return nullptr;
    }
    if (jieba == nullptr) {
        return nullptr;
    }
    g_tokenizerCache[cacheKey].reset(jieba);
    return static_cast<void*>(jieba);
}

bool CreateTokenizer()
{
    return GetOrCreateTokenizer(nullptr) != nullptr;
}

void DestroyTokenizer()
{
    std::lock_guard<std::mutex> lock(g_tokenizerMutex);
    g_tokenizerCache.clear();
}

bool ConvertString2Embedding(const char* srcStr, EmbeddingMap *embeddingMap, bool isKeywordExtractor,
    bool cutForSearch, const char* dictBasePath)
{
    cppjieba::Jieba* jieba = static_cast<cppjieba::Jieba*>(GetOrCreateTokenizer(dictBasePath));
    if (jieba == nullptr || srcStr == nullptr || embeddingMap == nullptr) {
        return false;
    }

    try {
        std::string sentence(srcStr);
        std::unordered_map<std::string, std::pair<uint32_t, float>> tokensMap;
        if (isKeywordExtractor && !cutForSearch) {
            std::vector<cppjieba::KeywordExtractor::Word> keywords;
            jieba->extractor.Extract(sentence, keywords, MAX_KEYWORD_NUM);
            for (const auto& keyword : keywords) {
                std::string lowerCaseKeyword = Convert2LowerCase(keyword.word);
                uint32_t hashValue = HashString2Uint32(lowerCaseKeyword);
                tokensMap[lowerCaseKeyword] = std::make_pair(hashValue, keyword.weight);
            }
            if (!tokensMap.empty()) {
                ConvertEmbeddingMap(tokensMap, embeddingMap);
                return true;
            }
        }

        std::vector<std::string> tokens;
        if (cutForSearch) {
            jieba->CutForSearch(sentence, tokens, true);
        } else {
            jieba->Cut(sentence, tokens, true);
        }

        for (const auto& token : tokens) {
            if (IsWhitespace(token)) {
                continue;
            }
            std::string lowerCaseToken = Convert2LowerCase(token);
            uint32_t hashValue = HashString2Uint32(lowerCaseToken);
            if (tokensMap.find(lowerCaseToken) == tokensMap.end()) {
                tokensMap[lowerCaseToken] = std::make_pair(hashValue, 1.0f);
            } else {
                tokensMap[lowerCaseToken].second += 1.0f;
            }
        }
        ConvertEmbeddingMap(tokensMap, embeddingMap);
        return true;
    } catch (...) {
        return false;
    }
}

#ifdef __cplusplus
}
#endif
